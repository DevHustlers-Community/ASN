defmodule AsnChat.Devices do
  @moduledoc """
  Device registry and lifecycle events.

  Device mutations are serialized per user by locking the `chat_users`
  projection row (`FOR NO KEY UPDATE`) inside the transaction. The partial
  unique index on `(user_id, identity_key_fingerprint) WHERE status = 'active'`
  remains the database backstop. Lock order is always user first, then device.

  Each mutation writes its event through `AsnChat.Events.Outbox` in the same
  transaction. Only public device metadata is stored and published; private key
  material never enters this service.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias AsnChat.Accounts
  alias AsnChat.Devices.{Device, Events, KeyPackage}
  alias AsnChat.Events.Outbox
  alias AsnChat.Repo

  @type error ::
          :identity_key_conflict
          | :user_not_found
          | :not_found
          | :duplicate
          | :limit_reached
          | Ecto.Changeset.t()
          | {:outbox_failed, Ecto.Changeset.t()}

  @type register_result ::
          {:ok, Device.t(), :created | :existing} | {:error, error()}

  @type revoke_result ::
          {:ok, Device.t(), :revoked | :already_revoked}
          | {:error, :not_found | Ecto.Changeset.t() | {:outbox_failed, Ecto.Changeset.t()}}

  @doc """
  Registers a device for `user_id`.

  Returns `{:ok, device, :created}` for a new active device and
  `{:ok, device, :existing}` for an idempotent retry with the same active
  fingerprint and byte-identical public key. A repeated active fingerprint
  with different key bytes returns `{:error, :identity_key_conflict}` and
  writes nothing.

  `attrs` accepts `platform`, `device_label`, `identity_key_public`, and
  `identity_key_fingerprint`. `identity_key_public` must already be decoded
  bytes; base64 decoding belongs to the HTTP layer. `user_id`, `id`, `status`,
  and timestamps are owned by this context.
  """
  @spec register_device(String.t(), map(), keyword()) :: register_result()
  def register_device(user_id, attrs, opts \\ []) do
    transact(fn ->
      user = Accounts.lock_user(user_id)

      if is_nil(user) do
        Repo.rollback(:user_not_found)
      end

      now = now()
      changeset = Device.registration_changeset(user.id, attrs, now: now)

      if changeset.valid? do
        register_changeset(changeset, opts)
      else
        Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Lists every device owned by `user_id`, including revoked devices.
  Ordering is stable: `created_at` ascending, then `id`.
  """
  @spec list_devices(String.t()) :: {:ok, [Device.t()]}
  def list_devices(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        {:ok,
         Repo.all(
           from d in Device,
             where: d.user_id == ^uuid,
             order_by: [asc: d.created_at, asc: d.id]
         )}

      :error ->
        {:ok, []}
    end
  end

  @doc """
  Stores one opaque KeyPackage for a device owned by `user_id` (ADR 0017).

  `bytes` must already be decoded; base64 decoding belongs to the HTTP layer.
  Ownership, active-device status, the per-device cap, and the SHA-256 digest
  are enforced here. Unknown or foreign devices answer `{:error, :not_found}`;
  repeated bytes answer `{:error, :duplicate}`. No outbox event is written:
  there is no KeyPackage event contract yet.
  """
  @spec upload_key_package(String.t(), String.t(), binary(), map(), keyword()) ::
          {:ok, KeyPackage.t()} | {:error, error()}
  def upload_key_package(user_id, device_id, bytes, attrs, opts \\ []) do
    opts = Keyword.merge(key_package_config(), opts)

    transact(fn ->
      user = Accounts.lock_user(user_id)

      if is_nil(user) do
        Repo.rollback(:not_found)
      end

      case fetch_active_device(user.id, device_id) do
        nil -> Repo.rollback(:not_found)
        device -> insert_key_package(device.id, bytes, attrs, opts)
      end
    end)
  end

  @doc """
  Lists KeyPackage metadata for a device owned by `user_id`.

  Bytes are not returned by this context; the deferred claim operation will be
  the only reader of `key_package`.
  """
  @spec list_key_packages(String.t(), String.t()) ::
          {:ok, [KeyPackage.t()]} | {:error, :not_found}
  def list_key_packages(user_id, device_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        case fetch_active_device(uuid, device_id, false) do
          nil ->
            {:error, :not_found}

          device ->
            {:ok,
             Repo.all(
               from k in KeyPackage,
                 where: k.device_id == ^device.id,
                 order_by: [asc: k.created_at, asc: k.id]
             )}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Revokes a device owned by `user_id`.

  Revocation is idempotent: an already revoked device returns
  `{:ok, device, :already_revoked}` and writes no new event. Unknown devices
  and devices owned by another user both return `{:error, :not_found}`.
  """
  @spec revoke_device(String.t(), String.t(), keyword()) :: revoke_result()
  def revoke_device(user_id, device_id, opts \\ []) do
    transact(fn ->
      user = Accounts.lock_user(user_id)

      if is_nil(user) do
        Repo.rollback(:not_found)
      end

      case fetch_device_for_update(user.id, device_id) do
        nil ->
          Repo.rollback(:not_found)

        %Device{status: :revoked} = device ->
          {:ok, device, :already_revoked}

        %Device{} = device ->
          revoke_changeset(device, opts)
      end
    end)
  end

  defp register_changeset(changeset, opts) do
    fingerprint = get_field(changeset, :identity_key_fingerprint)
    public_key = get_field(changeset, :identity_key_public)

    case find_active_device(get_field(changeset, :user_id), fingerprint) do
      %Device{identity_key_public: ^public_key} = existing ->
        {:ok, existing, :existing}

      %Device{} ->
        Repo.rollback(:identity_key_conflict)

      nil ->
        insert_device(changeset, opts)
    end
  end

  defp insert_device(changeset, opts) do
    case Repo.insert(changeset) do
      {:ok, device} ->
        record_registered_event(device, opts)

      {:error, insert_changeset} ->
        Repo.rollback(insert_failure(insert_changeset))
    end
  end

  defp record_registered_event(device, opts) do
    case Outbox.record(Events.registered(device, opts)) do
      {:ok, _event} -> {:ok, device, :created}
      {:error, event_changeset} -> Repo.rollback({:outbox_failed, event_changeset})
    end
  end

  defp revoke_changeset(device, opts) do
    changeset = Device.revoke_changeset(device, now())

    case Repo.update(changeset) do
      {:ok, revoked} ->
        record_revoked_event(revoked, opts)

      {:error, update_changeset} ->
        Repo.rollback(update_changeset)
    end
  end

  defp record_revoked_event(device, opts) do
    case Outbox.record(Events.revoked(device, opts)) do
      {:ok, _event} -> {:ok, device, :revoked}
      {:error, event_changeset} -> Repo.rollback({:outbox_failed, event_changeset})
    end
  end

  defp find_active_device(user_id, fingerprint) do
    Repo.one(
      from d in Device,
        where:
          d.user_id == ^user_id and
            d.identity_key_fingerprint == ^fingerprint and
            d.status == :active,
        lock: "FOR NO KEY UPDATE"
    )
  end

  defp insert_key_package(device_id, bytes, attrs, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    count =
      Repo.one(
        from k in KeyPackage,
          where: k.device_id == ^device_id and is_nil(k.consumed_at) and k.expires_at > ^now,
          select: count(k.id)
      )

    if count >= Keyword.fetch!(opts, :max_per_device) do
      Repo.rollback(:limit_reached)
    else
      changeset =
        KeyPackage.upload_changeset(
          device_id,
          :crypto.hash(:sha256, bytes),
          bytes,
          attrs,
          opts
        )

      case Repo.insert(changeset) do
        {:ok, key_package} -> {:ok, key_package}
        {:error, changeset} -> Repo.rollback(duplicate_or_changeset(changeset))
      end
    end
  end

  defp fetch_active_device(user_id, device_id, lock? \\ true) do
    case Ecto.UUID.cast(device_id) do
      {:ok, uuid} ->
        query =
          from d in Device,
            where: d.id == ^uuid and d.user_id == ^user_id and d.status == :active

        Repo.one(if lock?, do: lock(query, "FOR NO KEY UPDATE"), else: query)

      :error ->
        nil
    end
  end

  defp duplicate_or_changeset(changeset) do
    if unique_constraint_error?(changeset), do: :duplicate, else: changeset
  end

  defp key_package_config do
    [max_bytes: 196_608, max_lifetime_days: 90, max_per_device: 100]
    |> Keyword.merge(Application.get_env(:asn_chat, :key_packages, []))
  end

  defp fetch_device_for_update(user_id, device_id) do
    case Ecto.UUID.cast(device_id) do
      {:ok, uuid} ->
        Repo.one(
          from d in Device,
            where: d.id == ^uuid and d.user_id == ^user_id,
            lock: "FOR NO KEY UPDATE"
        )

      :error ->
        nil
    end
  end

  defp insert_failure(changeset) do
    if unique_constraint_error?(changeset) do
      :identity_key_conflict
    else
      changeset
    end
  end

  defp unique_constraint_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {_field, {_message, opts}} when is_list(opts) ->
        Keyword.get(opts, :constraint) == :unique

      _other ->
        false
    end)
  end

  defp transact(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end

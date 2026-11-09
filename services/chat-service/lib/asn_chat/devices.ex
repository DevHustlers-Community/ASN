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
  alias AsnChat.Devices.{Device, Events}
  alias AsnChat.Events.Outbox
  alias AsnChat.Repo

  @type error ::
          :identity_key_conflict
          | :user_not_found
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

defmodule AsnChat.Devices.KeyPackage do
  @moduledoc """
  Opaque public MLS KeyPackage material for one device (ADR 0007, ADR 0017).

  Only public protocol bytes are stored. The server never sees or derives
  private keys. The byte digest exists solely to reject duplicate bundles so a
  future one-time claim cannot hand the same KeyPackage to two initiators.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AsnChat.UUIDv7

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "device_key_packages" do
    field :device_id, Ecto.UUID
    field :key_package, :binary
    field :key_package_sha256, :binary
    field :ciphersuite, :integer
    field :created_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :last_resort, :boolean, default: false
    field :consumed_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @doc """
  Builds an upload changeset.

  `id`, `device_id`, `created_at`, and the digest are owned by the caller. A
  client cannot choose its own creation time or supply a digest for bytes it
  did not send.
  """
  @spec upload_changeset(String.t(), binary(), binary(), map(), keyword()) ::
          Ecto.Changeset.t()
  def upload_changeset(device_id, digest, bytes, attrs, opts \\ []) do
    now =
      Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:microsecond) end)

    max_bytes = Keyword.get(opts, :max_bytes, 131_072)
    max_days = Keyword.get(opts, :max_lifetime_days, 90)

    %__MODULE__{
      id: UUIDv7.generate(),
      device_id: device_id,
      key_package: bytes,
      key_package_sha256: digest,
      created_at: now,
      last_resort: false
    }
    |> cast(attrs, [:ciphersuite, :expires_at, :last_resort])
    |> validate_required([
      :id,
      :device_id,
      :key_package,
      :key_package_sha256,
      :ciphersuite,
      :expires_at,
      :created_at
    ])
    |> validate_number(:ciphersuite, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_bytes(bytes, max_bytes)
    |> validate_change(:key_package_sha256, fn _, value ->
      if is_binary(value) and byte_size(value) == 32,
        do: [],
        else: [key_package_sha256: "must be a SHA-256 digest"]
    end)
    |> validate_expiry(now, max_days)
    |> unique_constraint([:device_id, :key_package_sha256],
      name: :device_key_packages_device_digest_index
    )
  end

  defp validate_bytes(changeset, bytes, max_bytes) do
    cond do
      not is_binary(bytes) or byte_size(bytes) == 0 ->
        add_error(changeset, :key_package, "must be non-empty bytes")

      byte_size(bytes) > max_bytes ->
        add_error(changeset, :key_package, "exceeds the configured size limit")

      true ->
        changeset
    end
  end

  defp validate_expiry(changeset, now, max_days) do
    case Ecto.Changeset.get_field(changeset, :expires_at) do
      %DateTime{} = expires_at ->
        cond do
          DateTime.compare(expires_at, now) != :gt ->
            add_error(changeset, :expires_at, "must be in the future")

          DateTime.compare(expires_at, DateTime.add(now, max_days, :day)) == :gt ->
            add_error(changeset, :expires_at, "exceeds the maximum lifetime")

          true ->
            changeset
        end

      _other ->
        changeset
    end
  end
end

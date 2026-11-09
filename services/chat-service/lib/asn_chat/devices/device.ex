defmodule AsnChat.Devices.Device do
  @moduledoc """
  A cryptographic device identity owned by one Chat user.

  The server stores public material only. Private identity keys and session
  secrets never reach this service. Each row is one installed client/device;
  `identity_key_public` is opaque public protocol material and
  `identity_key_fingerprint` is a client-derived verification string.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AsnChat.UUIDv7

  @platforms [:android, :ios, :web]
  @statuses [:active, :revoked, :pending_verification]

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "chat_devices" do
    field :user_id, Ecto.UUID
    field :platform, Ecto.Enum, values: @platforms
    field :device_label, :string
    field :identity_key_public, :binary
    field :identity_key_fingerprint, :string
    field :registration_id, :integer
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :created_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @doc """
  Builds the registration changeset.

  `user_id`, `id`, `status`, and `created_at` are owned by the caller (the
  devices context). They are deliberately not cast from `attrs`: a caller must
  never be able to register a device for another user or to choose a lifecycle
  status directly.
  """
  @spec registration_changeset(String.t(), map(), keyword()) :: Ecto.Changeset.t()
  def registration_changeset(user_id, attrs, opts \\ []) do
    now =
      Keyword.get_lazy(opts, :now, fn ->
        DateTime.utc_now() |> DateTime.truncate(:microsecond)
      end)

    id = Keyword.get_lazy(opts, :id, &UUIDv7.generate/0)

    %__MODULE__{id: id, user_id: user_id, status: :active, created_at: now}
    |> cast(attrs, [
      :platform,
      :device_label,
      :identity_key_public,
      :identity_key_fingerprint
    ])
    |> validate_required([
      :user_id,
      :created_at,
      :platform,
      :identity_key_public,
      :identity_key_fingerprint
    ])
    |> validate_length(:device_label, max: 80, count: :codepoints)
    |> validate_length(:identity_key_fingerprint, min: 16, max: 128, count: :codepoints)
    |> validate_change(:identity_key_public, fn _, value ->
      if is_binary(value) and byte_size(value) > 0 do
        []
      else
        [identity_key_public: "must be a non-empty binary"]
      end
    end)
    |> validate_text(:device_label)
    |> validate_text(:identity_key_fingerprint)
    |> unique_constraint([:user_id, :identity_key_fingerprint],
      name: :chat_devices_user_active_fingerprint_index
    )
  end

  @doc """
  Marks the device revoked. The caller owns the transaction and the decision
  that the device is not already revoked.
  """
  @spec revoke_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def revoke_changeset(%__MODULE__{} = device, revoked_at \\ nil) do
    revoked_at =
      revoked_at ||
        DateTime.utc_now() |> DateTime.truncate(:microsecond)

    change(device, status: :revoked, revoked_at: revoked_at)
  end

  defp validate_text(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      cond do
        not String.valid?(value) ->
          [{field, "must be valid UTF-8"}]

        String.contains?(value, <<0>>) ->
          [{field, "must not contain null bytes"}]

        true ->
          []
      end
    end)
  end
end

defmodule AsnSocial.Accounts.User do
  @moduledoc "Social-owned account identity and authorization state."

  use Ecto.Schema
  import Ecto.Changeset

  alias AsnSocial.UUIDv7

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID

  schema "users" do
    field :auth0_sub, :string
    field :username, :string
    field :display_name, :string
    field :bio, :string
    field :avatar_key, :string
    field :cover_key, :string
    field :signup_country, :string
    field :device_type, :string

    field :status, Ecto.Enum,
      values: [:active, :suspended, :banned, :pending_deletion],
      default: :active

    field :sessions_valid_after, :utc_datetime_usec
    field :deletion_requested_at, :utc_datetime_usec
    field :purge_after, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(map(), keyword()) :: Ecto.Changeset.t()
  def create_changeset(attrs, opts \\ []) do
    user = %__MODULE__{}

    now =
      Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:microsecond) end)

    id = Keyword.get_lazy(opts, :id, &UUIDv7.generate/0)

    user
    |> cast(attrs, [
      :auth0_sub,
      :username,
      :display_name,
      :bio,
      :avatar_key,
      :cover_key,
      :signup_country,
      :device_type,
      :status,
      :sessions_valid_after,
      :deletion_requested_at,
      :purge_after
    ])
    |> put_change(:id, id)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
    |> validate_required([:id, :auth0_sub, :username, :status, :created_at, :updated_at])
    |> validate_length(:auth0_sub, min: 1, max: 255)
    |> validate_length(:username, min: 1, max: 30)
    |> validate_length(:display_name, max: 80)
    |> validate_inclusion(:status, [:active, :suspended, :banned, :pending_deletion])
    |> unique_constraint(:auth0_sub, name: :users_auth0_sub_index)
    |> unique_constraint(:username, name: :users_username_index)
  end

  @spec authorization_view(t()) :: map()
  def authorization_view(%__MODULE__{} = user) do
    %{
      user_id: user.id,
      status: Atom.to_string(user.status),
      sessions_valid_after: iso8601(user.sessions_valid_after)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp iso8601(%NaiveDateTime{} = value),
    do: DateTime.from_naive!(value, "Etc/UTC") |> DateTime.to_iso8601()
end

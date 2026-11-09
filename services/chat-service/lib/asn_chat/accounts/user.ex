defmodule AsnChat.Accounts.User do
  @moduledoc """
  Read-only projection of the account identity owned by Social.

  Chat stores only the fields it needs to address messages and to keep local
  account metadata. This schema is not the source of truth for accounts and
  must never be written by Chat domain contexts other than the projection
  consumer.
  """

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "chat_users" do
    field :username, :string
    field :display_name, :string
    field :avatar_key, :string
    field :show_presence, :boolean, default: true
    field :plan, :string, default: "free"
    field :hidden_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :source_version, :integer, default: 0
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}
end

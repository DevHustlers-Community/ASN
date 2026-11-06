defmodule AsnChat.Repo.Migrations.CreateChatUsers do
  use Ecto.Migration

  def up do
    create table(:chat_users, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # Read-only projection of social_db.users.username; Social is the source
      # of truth, so this column is intentionally not citext and has no unique
      # index here.
      add :username, :varchar, size: 30, null: false
      add :display_name, :varchar, size: 80
      add :avatar_key, :text
      add :show_presence, :boolean, null: false, default: true
      add :plan, :text, null: false, default: "free"
      add :hidden_at, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec
      add :source_version, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    # No unique index on `username` here: chat_users is a read-only projection
    # of the account identity owned by social_db.
  end

  def down do
    drop table(:chat_users)
  end
end

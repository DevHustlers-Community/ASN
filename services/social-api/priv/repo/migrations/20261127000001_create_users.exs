defmodule AsnSocial.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :auth0_sub, :text, null: false
      add :username, :citext, null: false
      add :display_name, :varchar, size: 80
      add :bio, :text
      add :avatar_key, :text
      add :cover_key, :text
      add :signup_country, :text
      add :device_type, :text
      add :status, :text, null: false, default: "active"
      add :sessions_valid_after, :timestamptz
      add :deletion_requested_at, :timestamptz
      add :purge_after, :timestamptz
      add :created_at, :timestamptz, null: false
      add :updated_at, :timestamptz, null: false
    end

    create unique_index(:users, [:auth0_sub], name: :users_auth0_sub_index)
    create unique_index(:users, [:username], name: :users_username_index)
    create index(:users, [:status, :id], name: :users_status_id_index)

    create constraint(
             :users,
             :users_status_check,
             check: "status IN ('active', 'suspended', 'banned', 'pending_deletion')"
           )

    create constraint(
             :users,
             :users_purge_after_check,
             check:
               "purge_after IS NULL OR (deletion_requested_at IS NOT NULL AND purge_after > deletion_requested_at)"
           )
  end

  def down do
    drop table(:users)
  end
end

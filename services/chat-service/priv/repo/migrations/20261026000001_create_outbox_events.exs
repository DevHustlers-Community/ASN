defmodule AsnChat.Repo.Migrations.CreateOutboxEvents do
  use Ecto.Migration

  def up do
    create table(:outbox_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :event_id, :uuid, null: false
      add :envelope, :map, null: false
      add :aggregate_type, :text
      add :aggregate_id, :uuid
      add :aggregate_version, :bigint
      add :published_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create unique_index(:outbox_events, [:event_id])

    create index(:outbox_events, [:aggregate_type, :aggregate_id, :aggregate_version],
             where: "published_at IS NULL"
           )
  end

  def down do
    drop table(:outbox_events)
  end
end

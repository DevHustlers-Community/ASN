defmodule AsnChat.Repo.Migrations.CreateProcessedEvents do
  use Ecto.Migration

  def up do
    create table(:processed_events, primary_key: false) do
      add :event_id, :uuid, primary_key: true, null: false

      add :processed_at, :utc_datetime_usec, null: false
      add :aggregate_type, :text
      add :aggregate_id, :uuid
      add :aggregate_version, :bigint
    end

    create index(:processed_events, [:aggregate_type, :aggregate_id])
  end

  def down do
    drop index(:processed_events, [:aggregate_type, :aggregate_id])

    drop table(:processed_events)
  end
end

defmodule AsnSocial.Repo.Migrations.CreateProcessedEvents do
  use Ecto.Migration

  def up do
    create table(:processed_events, primary_key: false) do
      add :event_id, :uuid, primary_key: true, null: false
      add :processed_at, :timestamptz, null: false
      add :aggregate_type, :text
      add :aggregate_id, :uuid
      add :aggregate_version, :bigint
    end

    create index(:processed_events, [:aggregate_type, :aggregate_id],
             name: :processed_events_aggregate_index
           )
  end

  def down do
    drop table(:processed_events)
  end
end

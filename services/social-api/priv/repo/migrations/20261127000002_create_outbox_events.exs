defmodule AsnSocial.Repo.Migrations.CreateOutboxEvents do
  use Ecto.Migration

  def up do
    create table(:outbox_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :type, :text, null: false
      add :aggregate_type, :text
      add :aggregate_id, :uuid
      add :aggregate_version, :bigint
      add :schema_version, :integer, null: false, default: 1
      add :occurred_at, :timestamptz, null: false
      add :payload, :map, null: false
      add :trace_id, :text
      add :created_at, :timestamptz, null: false
      add :published_at, :timestamptz
    end

    create constraint(
             :outbox_events,
             :outbox_events_schema_version_check,
             check: "schema_version >= 1"
           )

    create constraint(
             :outbox_events,
             :outbox_events_aggregate_fields_check,
             check:
               "(aggregate_type IS NULL AND aggregate_id IS NULL AND aggregate_version IS NULL) OR " <>
                 "(aggregate_type IS NOT NULL AND aggregate_id IS NOT NULL AND aggregate_version IS NOT NULL)"
           )

    create constraint(
             :outbox_events,
             :outbox_events_aggregate_version_check,
             check: "aggregate_version IS NULL OR aggregate_version >= 1"
           )

    create constraint(
             :outbox_events,
             :outbox_events_payload_object_check,
             check: "jsonb_typeof(payload) = 'object'"
           )

    create index(:outbox_events, [:created_at, :id],
             where: "published_at IS NULL",
             name: :outbox_events_unpublished_created_at_id_index
           )

    create unique_index(:outbox_events, [:aggregate_type, :aggregate_id, :aggregate_version],
             where: "aggregate_type IS NOT NULL",
             name: :outbox_events_aggregate_version_unique_index
           )
  end

  def down do
    drop table(:outbox_events)
  end
end

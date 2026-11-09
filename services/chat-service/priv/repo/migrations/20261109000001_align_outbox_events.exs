defmodule AsnChat.Repo.Migrations.AlignOutboxEvents do
  @moduledoc """
  Aligns `outbox_events` with the event fields the relay publishes
  (ADR 0015, architecture §3.18).

  `id` becomes the event id. The complete `envelope` copy is replaced by
  `type`, `schema_version`, `occurred_at`, `trace_id`, and `payload`; the relay
  rebuilds the envelope from these columns. The unused `updated_at` is dropped
  because the table is append-only except for `published_at`.
  """

  use Ecto.Migration

  def up do
    alter table(:outbox_events) do
      add :type, :text
      add :schema_version, :integer, default: 1
      add :occurred_at, :utc_datetime_usec
      add :trace_id, :text
      add :payload, :map
    end

    # Existing rows hold a valid envelope; copy its fields into the new columns
    # before the envelope column is removed. All timestamps are stored in UTC.
    execute("""
    UPDATE outbox_events
    SET type = envelope->>'type',
        schema_version = COALESCE((envelope->>'schema_version')::integer, 1),
        occurred_at = (envelope->>'occurred_at')::timestamptz AT TIME ZONE 'UTC',
        trace_id = envelope->>'trace_id',
        payload = envelope->'payload'
    """)

    execute("ALTER TABLE outbox_events ALTER COLUMN type SET NOT NULL")
    execute("ALTER TABLE outbox_events ALTER COLUMN schema_version SET NOT NULL")
    execute("ALTER TABLE outbox_events ALTER COLUMN occurred_at SET NOT NULL")
    execute("ALTER TABLE outbox_events ALTER COLUMN payload SET NOT NULL")

    execute("""
    ALTER TABLE outbox_events
      ADD CONSTRAINT outbox_events_schema_version_check CHECK (schema_version >= 1),
      ADD CONSTRAINT outbox_events_aggregate_fields_check CHECK (
        (aggregate_type IS NULL AND aggregate_id IS NULL AND aggregate_version IS NULL)
        OR (aggregate_type IS NOT NULL AND aggregate_id IS NOT NULL AND aggregate_version IS NOT NULL)
      ),
      ADD CONSTRAINT outbox_events_aggregate_version_check CHECK (
        aggregate_version IS NULL OR aggregate_version >= 1
      ),
      ADD CONSTRAINT outbox_events_payload_object_check CHECK (jsonb_typeof(payload) = 'object')
    """)

    create index(:outbox_events, [:created_at, :id],
             where: "published_at IS NULL",
             name: :outbox_events_unpublished_created_at_id_index
           )

    # The original per-aggregate index is superseded by the unique partial
    # index below (same columns, non-null aggregates only).
    drop index(:outbox_events, [:aggregate_type, :aggregate_id, :aggregate_version],
           name: :outbox_events_aggregate_type_aggregate_id_aggregate_version_ind
         )

    create unique_index(:outbox_events, [:aggregate_type, :aggregate_id, :aggregate_version],
             where: "aggregate_type IS NOT NULL",
             name: :outbox_events_aggregate_version_unique_index
           )

    execute("UPDATE outbox_events SET id = event_id")

    alter table(:outbox_events) do
      remove :event_id
      remove :envelope
      remove :updated_at
    end
  end

  def down do
    execute("ALTER TABLE outbox_events ADD COLUMN event_id uuid")
    execute("UPDATE outbox_events SET event_id = id")
    execute("ALTER TABLE outbox_events ALTER COLUMN event_id SET NOT NULL")
    execute("CREATE UNIQUE INDEX outbox_events_event_id_index ON outbox_events (event_id)")

    execute("ALTER TABLE outbox_events ADD COLUMN envelope jsonb")

    execute("""
    UPDATE outbox_events
    SET envelope =
      jsonb_build_object(
        'event_id', id,
        'type', type,
        'schema_version', schema_version,
        'occurred_at',
          to_char(occurred_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'payload', payload
      )
      || CASE
           WHEN aggregate_type IS NULL THEN '{}'::jsonb
           ELSE jsonb_build_object(
             'aggregate_type', aggregate_type,
             'aggregate_id', aggregate_id,
             'aggregate_version', aggregate_version
           )
         END
      || CASE
           WHEN trace_id IS NULL THEN '{}'::jsonb
           ELSE jsonb_build_object('trace_id', trace_id)
         END
    """)

    execute("ALTER TABLE outbox_events ALTER COLUMN envelope SET NOT NULL")

    execute("ALTER TABLE outbox_events ADD COLUMN updated_at timestamp(6) without time zone")
    execute("UPDATE outbox_events SET updated_at = created_at")
    execute("ALTER TABLE outbox_events ALTER COLUMN updated_at SET NOT NULL")

    drop index(:outbox_events, [:created_at, :id],
           name: :outbox_events_unpublished_created_at_id_index
         )

    drop index(:outbox_events, [:aggregate_type, :aggregate_id, :aggregate_version],
           name: :outbox_events_aggregate_version_unique_index
         )

    create index(:outbox_events, [:aggregate_type, :aggregate_id, :aggregate_version],
             where: "published_at IS NULL",
             name: :outbox_events_aggregate_type_aggregate_id_aggregate_version_ind
           )

    execute("ALTER TABLE outbox_events DROP CONSTRAINT outbox_events_schema_version_check")
    execute("ALTER TABLE outbox_events DROP CONSTRAINT outbox_events_aggregate_fields_check")
    execute("ALTER TABLE outbox_events DROP CONSTRAINT outbox_events_aggregate_version_check")
    execute("ALTER TABLE outbox_events DROP CONSTRAINT outbox_events_payload_object_check")

    alter table(:outbox_events) do
      remove :type
      remove :schema_version
      remove :occurred_at
      remove :trace_id
      remove :payload
    end
  end
end

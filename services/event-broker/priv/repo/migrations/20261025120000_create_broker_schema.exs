defmodule AsnEventBroker.Repo.Migrations.CreateBrokerSchema do
  use Ecto.Migration

  def up do
    create table(:subscriptions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :text, null: false
      add :consumer, :text, null: false
      add :event_types, {:array, :text}
      add :status, :text, null: false, default: "active"
      add :max_attempts, :integer, null: false, default: 5

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create constraint(:subscriptions, :subscriptions_name_check, check: "char_length(name) > 0")

    create constraint(:subscriptions, :subscriptions_consumer_check,
             check: "char_length(consumer) > 0"
           )

    create constraint(:subscriptions, :subscriptions_status_check,
             check: "status IN ('active', 'paused')"
           )

    create constraint(:subscriptions, :subscriptions_max_attempts_positive,
             check: "max_attempts > 0"
           )

    create constraint(:subscriptions, :subscriptions_event_types_cardinality,
             check: "event_types IS NULL OR cardinality(event_types) > 0"
           )

    create unique_index(:subscriptions, [:name])

    create table(:events, primary_key: false) do
      add :event_id, :uuid, primary_key: true, null: false
      add :type, :text, null: false
      add :schema_version, :integer, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :aggregate_type, :text
      add :aggregate_id, :uuid
      add :aggregate_version, :bigint
      add :trace_id, :text
      add :payload, :map, null: false
      add :content_hash, :text, null: false
      add :publisher, :text, null: false
      add :received_at, :utc_datetime_usec, null: false
    end

    create constraint(:events, :events_aggregate_fields_all_or_none,
             check: """
             (aggregate_type IS NULL AND aggregate_id IS NULL AND aggregate_version IS NULL)
             OR (aggregate_type IS NOT NULL AND aggregate_id IS NOT NULL AND aggregate_version IS NOT NULL)
             """
           )

    create constraint(:events, :events_content_hash_sha256,
             check: "char_length(content_hash) = 64"
           )

    create constraint(:events, :events_publisher_check, check: "char_length(publisher) > 0")

    create unique_index(:events, [:aggregate_type, :aggregate_id, :aggregate_version],
             where: "aggregate_type IS NOT NULL",
             name: :events_one_event_per_aggregate_version
           )

    create index(:events, [:type, :received_at])

    create table(:deliveries,
             primary_key: false,
             options: "WITH (fillfactor=80, autovacuum_vacuum_scale_factor=0.1)"
           ) do
      add :id, :uuid, primary_key: true, null: false

      add :subscription_id,
          references(:subscriptions, type: :uuid, column: :id, on_delete: :restrict),
          null: false

      add :event_id,
          references(:events, type: :uuid, column: :event_id, on_delete: :restrict),
          null: false

      add :aggregate_type, :text
      add :aggregate_id, :uuid
      add :aggregate_version, :bigint
      add :state, :text, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false
      add :lease_token_hash, :text
      add :lease_expires_at, :utc_datetime_usec
      add :next_attempt_at, :utc_datetime_usec
      add :last_error_kind, :text
      add :last_error_message, :text
      add :delivered_at, :utc_datetime_usec
      add :dead_lettered_at, :utc_datetime_usec
      add :skipped_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create constraint(:deliveries, :deliveries_state_check,
             check: "state IN ('pending', 'leased', 'delivered', 'dead', 'skipped')"
           )

    create constraint(:deliveries, :deliveries_attempts_non_negative, check: "attempts >= 0")

    create constraint(:deliveries, :deliveries_max_attempts_positive, check: "max_attempts > 0")

    create constraint(:deliveries, :deliveries_lease_expiry_matches_state,
             check: "(state = 'leased') = (lease_expires_at IS NOT NULL)"
           )

    create constraint(:deliveries, :deliveries_lease_token_matches_state,
             check: "(state IN ('leased', 'delivered')) = (lease_token_hash IS NOT NULL)"
           )

    create constraint(:deliveries, :deliveries_delivered_at_matches_state,
             check: "(state = 'delivered') = (delivered_at IS NOT NULL)"
           )

    create constraint(:deliveries, :deliveries_dead_lettered_at_matches_state,
             check: "(state = 'dead') = (dead_lettered_at IS NOT NULL)"
           )

    create constraint(:deliveries, :deliveries_skipped_at_matches_state,
             check: "(state = 'skipped') = (skipped_at IS NOT NULL)"
           )

    create unique_index(:deliveries, [:subscription_id, :event_id])

    create unique_index(:deliveries, [:subscription_id, :aggregate_type, :aggregate_id],
             where: "state = 'leased'",
             name: :deliveries_one_leased_per_aggregate
           )

    create index(:deliveries, [
             :subscription_id,
             :aggregate_type,
             :aggregate_id,
             :aggregate_version
           ])

    create index(:deliveries, [:subscription_id, :next_attempt_at], where: "state = 'pending'")

    create index(:deliveries, [:lease_expires_at], where: "state = 'leased'")

    create index(:deliveries, [:subscription_id, :dead_lettered_at], where: "state = 'dead'")

    create table(:service_credentials, primary_key: false) do
      add :credential_id, :uuid, primary_key: true, null: false
      add :service_name, :text, null: false
      add :token_hash, :text, null: false
      add :scopes, {:array, :text}, null: false
      add :allowed_event_types, {:array, :text}
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create constraint(:service_credentials, :service_credentials_service_name_check,
             check: "char_length(service_name) > 0"
           )

    create constraint(:service_credentials, :service_credentials_token_hash_sha256,
             check: "char_length(token_hash) = 64"
           )

    create constraint(:service_credentials, :service_credentials_scopes_known,
             check: """
             cardinality(scopes) > 0
             AND scopes <@ ARRAY['publish', 'consume', 'admin']
             """
           )

    create constraint(:service_credentials, :service_credentials_allowed_event_types_cardinality,
             check: "allowed_event_types IS NULL OR cardinality(allowed_event_types) > 0"
           )

    create unique_index(:service_credentials, [:token_hash])
    create index(:service_credentials, [:service_name])

    create table(:audit_log, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :actor_credential_id, :uuid, null: false
      add :action, :text, null: false
      add :target, :text, null: false
      add :params, :map, null: false
      add :at, :utc_datetime_usec, null: false
    end

    create constraint(:audit_log, :audit_log_action_check, check: "char_length(action) > 0")

    create constraint(:audit_log, :audit_log_target_check, check: "char_length(target) > 0")

    create index(:audit_log, [:at])
  end

  def down do
    drop table(:audit_log)
    drop table(:service_credentials)
    drop table(:deliveries)
    drop table(:events)
    drop table(:subscriptions)
  end
end

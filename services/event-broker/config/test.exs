import Config

config :asn_event_broker, AsnEventBroker.Repo,
  url:
    System.get_env(
      "BROKER_TEST_DATABASE_URL",
      "postgres://asn_broker:change_me@localhost:5432/broker_db_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :logger, level: :warning

config :asn_event_broker, :start_workers, false
config :asn_event_broker, :http, enabled: false
config :asn_event_broker, :bootstrap_admin, false

# No background gauge refresh in tests: the metrics process has no sandbox
# checkout, and tests call AsnEventBroker.Web.Metrics.refresh/0 inside theirs.
config :asn_event_broker, :metrics, gauge_interval_ms: 0

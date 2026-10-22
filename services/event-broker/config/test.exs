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

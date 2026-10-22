import Config

config :asn_event_broker, AsnEventBroker.Repo,
  url:
    System.get_env(
      "BROKER_DATABASE_URL",
      "postgres://asn_broker:change_me@localhost:5432/broker_db"
    ),
  stacktrace: true,
  pool_size: 10

config :logger, :default_formatter, format: "[$level] $message\n"

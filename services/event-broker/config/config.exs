import Config

config :asn_event_broker,
  ecto_repos: [AsnEventBroker.Repo],
  generators: [timestamp_type: :utc_datetime]

# Defaults from ADR 0008; all values are runtime-tunable configuration, not
# contract. Override per environment (dev.exs, runtime.exs).
config :asn_event_broker, :delivery,
  lease_seconds: 30,
  max_in_flight: 10,
  backoff_base_ms: 1_000,
  backoff_cap_ms: 300_000,
  max_attempts: 5,
  sweep_interval_ms: 1_000,
  long_poll_max_ms: 20_000,
  reaper_interval_ms: 5_000

# Scheduled workers run against the real database; disabled under the test
# sandbox (their logic is tested by direct invocation).
config :asn_event_broker, :start_workers, true

# Retention defaults from ADR 0008 §8: delivered 24 h, dead/skipped 30 days,
# event log 7 days (a deletion floor, not a replay promise).
config :asn_event_broker, :retention,
  delivered_hours: 24,
  terminal_days: 30,
  event_log_days: 7

# The HTTP edge (ADR 0008 §2): Plug + Bandit at the edge only.
config :asn_event_broker, :http,
  enabled: true,
  port: 4004

config :asn_event_broker, :bootstrap_admin, true

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"

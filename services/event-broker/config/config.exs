import Config

config :asn_event_broker,
  ecto_repos: [AsnEventBroker.Repo],
  generators: [timestamp_type: :utc_datetime]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"

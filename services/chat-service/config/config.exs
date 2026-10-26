# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :asn_chat,
  ecto_repos: [AsnChat.Repo],
  generators: [timestamp_type: :utc_datetime]

# Broker relay (ADR 0008 §5 producer contract). Publishes committed outbox
# rows to the broker; disabled under the test sandbox (relays are exercised
# by direct invocation).
config :asn_chat, :events_relay,
  enabled: true,
  interval_ms: 1_000,
  publish_timeout_ms: 5_000

# Configure the endpoint
config :asn_chat, AsnChatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AsnChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AsnChat.PubSub

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

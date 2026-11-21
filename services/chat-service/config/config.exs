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

# REST authentication and request policy (ADR 0016). Values are overridden per
# environment; the identifiers below are development placeholders and are not
# network endpoints.
config :asn_chat, :auth,
  issuer: "https://asn.example/",
  audience: "https://api.asn.example/chat",
  user_id_claim: "https://asn.example/user_id",
  allowed_algs: ["RS256"],
  leeway_seconds: 30,
  jwks: nil,
  jwks_url: nil,
  jwks_cache_ms: 300_000,
  jwks_max_stale_ms: 3_600_000,
  jwks_timeout_ms: 2_000,
  authorization_adapter: AsnChat.Authorization.SocialClient,
  authorization_timeout_ms: 300,
  social_base_url: nil,
  m2m_token: nil

config :asn_chat, :request_limits, max_body_bytes: 262_144

# KeyPackage upload limits (ADR 0017). Operational configuration, not contract.
config :asn_chat, :key_packages,
  max_bytes: 131_072,
  max_lifetime_days: 90,
  max_per_device: 100

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

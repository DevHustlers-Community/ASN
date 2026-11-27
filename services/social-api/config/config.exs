import Config

config :asn_social,
  ecto_repos: [AsnSocial.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :asn_social, :auth,
  issuer: "https://asn.example/",
  audience: "https://api.asn.example/social",
  required_scope: "social:authorization:read",
  allowed_algs: ["RS256"],
  leeway_seconds: 30,
  jwks: nil,
  jwks_url: nil,
  jwks_cache_ms: 300_000,
  jwks_max_stale_ms: 3_600_000,
  jwks_timeout_ms: 2_000

config :asn_social, :request_limits, max_body_bytes: 262_144

config :asn_social, AsnSocialWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AsnSocialWeb.ErrorJSON],
    layout: false
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

import Config

config :asn_social, AsnSocial.Repo,
  url:
    System.get_env(
      "SOCIAL_DATABASE_URL",
      "postgres://asn_social:change_me@localhost:5432/social_db"
    ),
  stacktrace: true,
  pool_size: 10

config :asn_social, AsnSocialWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    System.get_env(
      "SECRET_KEY_BASE",
      "dev-only-secret-key-base-change-me-0123456789abcdef0123456789abcdef"
    ),
  watchers: []

config :logger, :default_formatter, format: "[$level] $message\n"

config :asn_social, :auth, dev_keys_path: Path.expand("../priv/dev/auth_key.json", __DIR__)

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

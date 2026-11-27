import Config

config :asn_social, AsnSocial.Repo,
  url:
    System.get_env(
      "SOCIAL_TEST_DATABASE_URL",
      "postgres://asn_social:change_me@localhost:5432/social_db_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :asn_social, AsnSocialWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  secret_key_base:
    System.get_env(
      "SECRET_KEY_BASE",
      "test-only-secret-key-base-change-me-0123456789abcdef0123456789abcdef"
    ),
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix,
  sort_verified_routes_query_params: true

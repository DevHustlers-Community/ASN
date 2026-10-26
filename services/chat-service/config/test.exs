import Config

# Configure your database
config :asn_chat, AsnChat.Repo,
  url:
    System.get_env(
      "CHAT_TEST_DATABASE_URL",
      "postgres://asn_chat:change_me@localhost:5432/chat_db_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :asn_chat, AsnChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    System.get_env(
      "SECRET_KEY_BASE",
      "test-only-secret-key-base-change-me-0123456789abcdef0123456789abcdef"
    ),
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :asn_chat, :events_relay, enabled: false, interval_ms: 1_000, publish_timeout_ms: 5_000

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

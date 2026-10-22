import Config

if config_env() == :prod do
  database_url =
    System.get_env("BROKER_DATABASE_URL") ||
      System.get_env("DATABASE_URL") ||
      raise """
      environment variable BROKER_DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :asn_event_broker, AsnEventBroker.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
end

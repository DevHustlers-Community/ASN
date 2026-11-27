import Config

if System.get_env("PHX_SERVER") do
  config :asn_social, AsnSocialWeb.Endpoint, server: true
end

config :asn_social, AsnSocialWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("SOCIAL_API_PORT", "4001"))]

env = fn name ->
  case System.get_env(name) do
    nil -> nil
    "" -> nil
    value -> value
  end
end

auth = Application.get_env(:asn_social, :auth, [])

config :asn_social,
       :auth,
       Keyword.merge(auth,
         issuer: env.("ASN_SOCIAL_AUTH_ISSUER") || auth[:issuer],
         audience: env.("ASN_SOCIAL_AUTH_AUDIENCE") || auth[:audience],
         required_scope: env.("ASN_SOCIAL_AUTH_SCOPE") || auth[:required_scope],
         jwks_url: env.("ASN_SOCIAL_AUTH_JWKS_URL") || auth[:jwks_url]
       )

if config_env() == :prod do
  database_url =
    System.get_env("SOCIAL_DATABASE_URL") ||
      raise "SOCIAL_DATABASE_URL is required in production"

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :asn_social, AsnSocial.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is required in production"

  config :asn_social, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :asn_social, AsnSocialWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST", "example.com"), port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end

defmodule Mix.Tasks.AsnSocial.DevToken do
  @shortdoc "Mints a development M2M JWT for Social internal APIs"

  @moduledoc """
  Usage:

      mix asn_social.dev_token --client-id chat-service

  The token is signed with the gitignored development key and is only allowed
  in the dev environment.
  """

  use Mix.Task

  @default_ttl 900

  @impl true
  def run(args) do
    unless Mix.env() == :dev do
      Mix.raise("asn_social.dev_token is only available in the dev environment")
    end

    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [client_id: :string, scope: :string, ttl: :integer])

    client_id = opts[:client_id] || Mix.raise("--client-id is required")
    ttl = opts[:ttl] || @default_ttl

    if ttl <= 0, do: Mix.raise("--ttl must be a positive integer")

    auth = Application.get_env(:asn_social, :auth, [])
    path = auth[:dev_keys_path] || Mix.raise("dev_keys_path is not configured")
    scope = opts[:scope] || auth[:required_scope] || Mix.raise("required_scope is not configured")

    {:ok, jwk} = AsnSocial.Auth.DevKeys.key(path)
    {_fields, map} = JOSE.JWK.to_map(jwk)
    now = System.system_time(:second)

    claims = %{
      "iss" => auth[:issuer],
      "aud" => auth[:audience],
      "sub" => client_id,
      "iat" => now,
      "exp" => now + ttl,
      "scope" => scope
    }

    token =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => map["kid"]}, claims)
      |> JOSE.JWS.compact()
      |> elem(1)

    Mix.shell().info(token)
  end
end

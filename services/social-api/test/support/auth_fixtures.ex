defmodule AsnSocial.AuthFixtures do
  @moduledoc "Test-only Auth0-style M2M token issuer with per-run RSA keys."

  @key {__MODULE__, :key_material}

  def setup! do
    {_jwk, _kid, jwks} = key_material()
    auth = Application.get_env(:asn_social, :auth, [])
    Application.put_env(:asn_social, :auth, Keyword.merge(auth, jwks: jwks))
    :ok
  end

  def token(opts \\ []) do
    claims = Keyword.get_lazy(opts, :claims, fn -> default_claims(opts) end)
    sign(claims, opts)
  end

  def sign(claims, opts \\ []) do
    {jwk, kid, _jwks} = Keyword.get_lazy(opts, :key_material, &key_material/0)
    jwk = Keyword.get(opts, :signing_key, jwk)
    header = %{"alg" => Keyword.get(opts, :alg, "RS256"), "kid" => Keyword.get(opts, :kid, kid)}

    JOSE.JWT.sign(jwk, header, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  def other_key, do: JOSE.JWK.generate_key({:rsa, 2048})

  def claims(opts \\ []), do: default_claims(opts)

  defp default_claims(opts) do
    auth = Application.get_env(:asn_social, :auth, [])
    now = System.system_time(:second)

    %{
      "iss" => Keyword.get(opts, :issuer, auth[:issuer]),
      "aud" => Keyword.get(opts, :audience, auth[:audience]),
      "sub" => Keyword.get(opts, :client_id, "chat-service"),
      "iat" => Keyword.get(opts, :iat, now),
      "exp" => Keyword.get(opts, :exp, now + 900),
      "scope" => Keyword.get(opts, :scope, auth[:required_scope])
    }
  end

  defp key_material do
    case :persistent_term.get(@key, nil) do
      nil ->
        jwk = JOSE.JWK.generate_key({:rsa, 2048})
        {_fields, map} = JOSE.JWK.to_map(jwk)
        kid = "test-key"
        map = Map.put(map, "kid", kid)
        jwk = JOSE.JWK.from_map(map)

        {_public_fields, public} = JOSE.JWK.to_map(JOSE.JWK.to_public(jwk))
        public = Map.put(public, "kid", kid)

        material = {jwk, kid, %{"keys" => [public]}}
        :persistent_term.put(@key, material)
        material

      material ->
        material
    end
  end
end

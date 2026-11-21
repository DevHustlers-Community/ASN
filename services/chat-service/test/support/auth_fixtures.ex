defmodule AsnChat.AuthFixtures do
  @moduledoc """
  Test-only JWT issuer.

  Generates one RSA key per test run, publishes its public JWKS through the
  `:auth` configuration, and signs tokens with the same claim shape as the
  production path. No real secrets or user data are involved.
  """

  @key {__MODULE__, :key_material}

  @doc """
  Installs the test JWKS. Call once from `test_helper.exs`.
  """
  def setup! do
    {_jwk, _kid, jwks} = key_material()
    auth = Application.get_env(:asn_chat, :auth, [])
    Application.put_env(:asn_chat, :auth, Keyword.merge(auth, jwks: jwks))
    :ok
  end

  @doc """
  Signs a token for `user_id` with the default test claims.
  """
  def token(user_id, opts \\ []) do
    claims = Keyword.get_lazy(opts, :claims, fn -> default_claims(user_id, opts) end)
    sign(claims, opts)
  end

  @doc """
  Signs an arbitrary claims map.
  """
  def sign(claims, opts \\ []) do
    {jwk, kid, _jwks} = Keyword.get_lazy(opts, :key_material, &key_material/0)

    jwk =
      case Keyword.get(opts, :signing_key) do
        nil -> jwk
        other -> other
      end

    header = %{
      "alg" => Keyword.get(opts, :alg, "RS256"),
      "kid" => Keyword.get(opts, :kid, kid)
    }

    JOSE.JWT.sign(jwk, header, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  @doc """
  Returns a second, unrelated key for wrong-signature tests.
  """
  def other_key do
    JOSE.JWK.generate_key({:rsa, 2048})
  end

  @doc """
  Returns the default claims map for a user id.
  """
  def claims(user_id, opts \\ []), do: default_claims(user_id, opts)

  defp default_claims(user_id, opts) do
    auth = Application.get_env(:asn_chat, :auth, [])
    now = System.system_time(:second)

    %{
      "iss" => Keyword.get(opts, :issuer, auth[:issuer]),
      "aud" => Keyword.get(opts, :audience, auth[:audience]),
      "sub" => "test|" <> user_id,
      "iat" => Keyword.get(opts, :iat, now),
      "exp" => Keyword.get(opts, :exp, now + 900),
      "scope" => Keyword.get(opts, :scope, "chat:read chat:write chat:devices"),
      auth[:user_id_claim] => user_id
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

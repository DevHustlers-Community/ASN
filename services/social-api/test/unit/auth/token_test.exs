defmodule AsnSocial.Auth.TokenTest do
  use ExUnit.Case, async: true

  alias AsnSocial.Auth.Token
  alias AsnSocial.AuthFixtures

  test "verifies a scoped M2M token" do
    token = AuthFixtures.token(client_id: "chat-service", scope: "social:authorization:read")

    assert {:ok, claims} = Token.verify(token)
    assert claims.client_id == "chat-service"
    assert claims.scopes == ["social:authorization:read"]
    assert %DateTime{} = claims.issued_at
    assert %DateTime{} = claims.expires_at
  end

  test "rejects expired tokens" do
    token = AuthFixtures.token(exp: System.system_time(:second) - 60)
    assert {:error, :expired} = Token.verify(token)
  end

  test "rejects wrong issuer and audience" do
    assert {:error, :invalid_token} =
             Token.verify(AuthFixtures.token(issuer: "https://wrong.example/"))

    assert {:error, :invalid_token} =
             Token.verify(AuthFixtures.token(audience: "https://wrong.example/api"))
  end

  test "rejects a token signed by another key" do
    token = AuthFixtures.token(signing_key: AuthFixtures.other_key())
    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "rejects an unknown key id" do
    token = AuthFixtures.token(kid: "unknown-key")
    assert {:error, :unknown_key} = Token.verify(token)
  end

  test "fails closed when no key source is configured" do
    token = AuthFixtures.token()

    assert {:error, :jwks_unavailable} =
             Token.verify(token, jwks: nil, dev_keys_path: nil, jwks_url: nil)
  end
end

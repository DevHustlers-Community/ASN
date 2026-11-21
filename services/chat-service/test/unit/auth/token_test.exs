defmodule AsnChat.Auth.TokenTest do
  use ExUnit.Case, async: true

  alias AsnChat.Auth.Token
  alias AsnChat.AuthFixtures

  @user_id "0190f1e2-6d7e-7f80-b192-3d4e5f607182"

  test "verifies a valid token and returns canonical claims" do
    token = AuthFixtures.token(@user_id)

    assert {:ok, claims} = Token.verify(token)
    assert claims.user_id == @user_id
    assert %DateTime{} = claims.issued_at
    assert %DateTime{} = claims.expires_at
    assert "chat:read" in claims.scopes
    assert "chat:devices" in claims.scopes
  end

  test "rejects an expired token" do
    now = System.system_time(:second)
    token = AuthFixtures.token(@user_id, iat: now - 1_000, exp: now - 100)

    assert {:error, :expired} = Token.verify(token)
  end

  test "rejects a token from the wrong issuer" do
    token = AuthFixtures.token(@user_id, issuer: "https://not-asn.example/")

    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "rejects a token for the wrong audience" do
    token = AuthFixtures.token(@user_id, audience: "https://api.asn.example/social")

    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "rejects a token without the namespaced user id claim" do
    claim = Application.get_env(:asn_chat, :auth)[:user_id_claim]
    claims = AuthFixtures.claims(@user_id) |> Map.delete(claim)
    token = AuthFixtures.sign(claims)

    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "rejects a token whose user id claim is not a UUID" do
    claim = Application.get_env(:asn_chat, :auth)[:user_id_claim]
    claims = Map.put(AuthFixtures.claims(@user_id), claim, "not-a-uuid")
    token = AuthFixtures.sign(claims)

    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "rejects a token signed by the wrong key" do
    token = AuthFixtures.token(@user_id, signing_key: AuthFixtures.other_key())

    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "rejects an unknown kid" do
    token = AuthFixtures.token(@user_id, kid: "unknown-kid")

    assert {:error, :unknown_key} = Token.verify(token)
  end

  test "rejects a tampered token" do
    token = AuthFixtures.token(@user_id)

    assert {:error, :invalid_token} = Token.verify(token <> "x")
  end

  test "rejects an algorithm outside the allow-list" do
    token =
      AuthFixtures.sign(
        AuthFixtures.claims(@user_id),
        alg: "HS256",
        signing_key: JOSE.JWK.generate_key({:oct, 32})
      )

    assert {:error, :invalid_token} = Token.verify(token)
  end
end

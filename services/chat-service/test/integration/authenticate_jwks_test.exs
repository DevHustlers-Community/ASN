defmodule AsnChatWeb.AuthenticateJwksTest do
  use AsnChatWeb.ConnCase, async: true

  alias AsnChat.Auth.Token
  alias AsnChat.AuthFixtures
  alias AsnChatWeb.Plugs.Authenticate

  @user_id "0190f1e2-6d7e-7f80-b192-3d4e5f607182"

  test "token verification reports an unavailable JWKS without any key source" do
    token = AuthFixtures.token(@user_id)

    assert {:error, :jwks_unavailable} =
             Token.verify(token, jwks: nil, jwks_url: nil, dev_keys_path: nil)
  end

  test "JWKS failure and authorization failure use distinct 503 codes", %{conn: conn} do
    jwks_conn = Authenticate.handle_error(conn, {:error, :jwks_unavailable})

    assert jwks_conn.status == 503
    assert %{"code" => "service_unavailable"} = Jason.decode!(jwks_conn.resp_body)

    auth_conn = Authenticate.handle_error(build_conn(), {:error, :unavailable})

    assert auth_conn.status == 503
    assert %{"code" => "authorization_unavailable"} = Jason.decode!(auth_conn.resp_body)
  end
end

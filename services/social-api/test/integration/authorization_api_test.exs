defmodule AsnSocialWeb.AuthorizationApiTest do
  use AsnSocialWeb.ConnCase, async: true

  alias AsnSocial.Accounts
  alias AsnSocial.AuthFixtures

  test "health endpoints do not require authentication" do
    assert %{status: 200, resp_body: body} = get(build_conn(), "/healthz")
    assert Jason.decode!(body) == %{"status" => "up"}

    assert %{status: 200, resp_body: body} = get(build_conn(), "/readyz")
    assert Jason.decode!(body) == %{"status" => "ready"}
  end

  test "returns RFC 9457 unauthorized without a token" do
    conn = get(build_conn(), "/internal/v1/users/#{Ecto.UUID.generate()}/authorization")

    assert conn.status == 401
    assert get_resp_header(conn, "content-type") == ["application/problem+json; charset=utf-8"]

    body = Jason.decode!(conn.resp_body)
    assert body["code"] == "unauthorized"
    assert body["request_id"]
  end

  test "requires the authorization read scope" do
    token = AuthFixtures.token(scope: "social:read")
    conn = authorization_request(token, Ecto.UUID.generate())

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["code"] == "forbidden"
  end

  test "returns active account authorization for a scoped M2M token" do
    assert {:ok, user} =
             Accounts.create_user(%{auth0_sub: "auth0|active", username: "active-user"})

    conn = authorization_request(AuthFixtures.token(), user.id)

    assert conn.status == 200

    assert Jason.decode!(conn.resp_body) == %{
             "user_id" => user.id,
             "status" => "active",
             "sessions_valid_after" => nil
           }
  end

  test "returns suspended status and session cutoff" do
    cutoff = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, user} =
             Accounts.create_user(%{
               auth0_sub: "auth0|suspended-api",
               username: "suspended-api-user",
               status: :suspended,
               sessions_valid_after: cutoff
             })

    conn = authorization_request(AuthFixtures.token(), user.id)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "suspended"
    assert body["sessions_valid_after"] == DateTime.to_iso8601(cutoff)
  end

  test "unknown and malformed users are not found" do
    token = AuthFixtures.token()

    assert authorization_request(token, Ecto.UUID.generate()).status == 404
    assert authorization_request(token, "not-a-uuid").status == 404
  end

  test "expired tokens are unauthorized" do
    token = AuthFixtures.token(exp: System.system_time(:second) - 60)
    assert authorization_request(token, Ecto.UUID.generate()).status == 401
  end

  defp authorization_request(token, user_id) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> get("/internal/v1/users/#{user_id}/authorization")
  end
end

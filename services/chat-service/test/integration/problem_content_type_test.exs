defmodule AsnChatWeb.ProblemContentTypeTest do
  use AsnChatWeb.ConnCase, async: true

  test "unknown routes return Problem Details content type", %{conn: conn} do
    conn = get(conn, "/api/v1/does-not-exist")

    assert conn.status == 404
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/problem+json"
    assert %{"code" => "not_found", "request_id" => request_id} = Jason.decode!(conn.resp_body)
    assert is_binary(request_id)
  end

  test "unauthenticated errors also use Problem Details content type", %{conn: conn} do
    conn = get(conn, "/api/v1/devices")

    assert conn.status == 401
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/problem+json"
  end
end

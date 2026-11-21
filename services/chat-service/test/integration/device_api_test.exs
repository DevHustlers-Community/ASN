defmodule AsnChatWeb.DeviceApiTest do
  use AsnChatWeb.ConnCase, async: true

  import AsnChat.ChatFixtures

  alias AsnChat.AuthFixtures
  alias AsnChat.Authorization.TestAdapter

  setup do
    user = user_fixture()
    %{user: user, token: AuthFixtures.token(user.id)}
  end

  defp authenticated(conn, token) do
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp json_request(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> send_request(method, path, Jason.encode!(body))
  end

  defp send_request(conn, method, path, body) do
    case method do
      :post -> post(conn, path, body)
      :get -> get(conn, path)
    end
  end

  defp content_type(conn) do
    conn |> get_resp_header("content-type") |> List.first() || ""
  end

  defp device_body(overrides \\ %{}) do
    Map.merge(
      %{
        "platform" => "android",
        "device_label" => "Pixel test",
        "identity_key_public" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "identity_key_fingerprint" => "fingerprint-#{System.unique_integer([:positive])}-abcdef"
      },
      overrides
    )
  end

  test "rejects a missing bearer token with Problem Details", %{conn: conn} do
    conn = get(conn, "/api/v1/devices")

    assert conn.status == 401
    assert content_type(conn) =~ "application/problem+json"

    assert %{"code" => "unauthorized", "status" => 401, "request_id" => request_id} =
             Jason.decode!(conn.resp_body)

    assert is_binary(request_id) and request_id != ""
  end

  test "rejects a token whose signature does not verify", %{conn: conn, user: user} do
    token = AuthFixtures.token(user.id, signing_key: AuthFixtures.other_key())

    conn =
      conn
      |> authenticated(token)
      |> get("/api/v1/devices")

    assert conn.status == 401
    assert %{"code" => "unauthorized"} = Jason.decode!(conn.resp_body)
  end

  test "rejects a token without the required scope", %{conn: conn, user: user} do
    token = AuthFixtures.token(user.id, scope: "chat:read")

    conn =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", device_body())

    assert conn.status == 403
    assert %{"code" => "forbidden"} = Jason.decode!(conn.resp_body)
  end

  test "returns 403 when the authoritative check says the account is inactive", %{
    conn: conn,
    user: user,
    token: token
  } do
    Process.put(:asn_chat_authorization_adapter, TestAdapter)
    Process.put({:asn_chat_authorization, user.id}, {:error, :inactive})

    conn =
      conn
      |> authenticated(token)
      |> get("/api/v1/devices")

    assert conn.status == 403
    assert %{"code" => "forbidden"} = Jason.decode!(conn.resp_body)
  end

  test "returns 503 when the authoritative check is unavailable", %{
    conn: conn,
    user: user,
    token: token
  } do
    Process.put(:asn_chat_authorization_adapter, TestAdapter)
    Process.put({:asn_chat_authorization, user.id}, {:error, :unavailable})

    conn =
      conn
      |> authenticated(token)
      |> get("/api/v1/devices")

    assert conn.status == 503
    assert %{"code" => "authorization_unavailable"} = Jason.decode!(conn.resp_body)
  end

  test "registers a device and returns the public DeviceView", %{
    conn: conn,
    user: user,
    token: token
  } do
    body = device_body()

    conn =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", body)

    assert conn.status == 201
    assert content_type(conn) =~ "application/json"

    view = Jason.decode!(conn.resp_body)
    assert view["device_id"] |> is_binary()
    assert String.at(view["device_id"], 14) == "7"
    assert view["platform"] == "android"
    assert view["device_label"] == "Pixel test"
    assert view["identity_key_public"] == body["identity_key_public"]
    assert view["identity_key_fingerprint"] == body["identity_key_fingerprint"]
    assert view["status"] == "active"
    assert view["created_at"]
    refute Map.has_key?(view, "revoked_at")

    assert [device] = AsnChat.Repo.all(AsnChat.Devices.Device)
    assert device.user_id == user.id
  end

  test "re-registering the same active key is an idempotent 200", %{
    conn: conn,
    token: token
  } do
    body = device_body()

    first =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", body)

    second =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", body)

    assert first.status == 201
    assert second.status == 200

    assert Jason.decode!(first.resp_body)["device_id"] ==
             Jason.decode!(second.resp_body)["device_id"]
  end

  test "the same fingerprint with different key bytes answers 409", %{
    conn: conn,
    token: token
  } do
    body = device_body()

    assert conn
           |> authenticated(token)
           |> json_request(:post, "/api/v1/devices", body)
           |> Map.fetch!(:status) == 201

    conflict =
      body
      |> Map.put("identity_key_public", Base.encode64(:crypto.strong_rand_bytes(32)))

    conn =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", conflict)

    assert conn.status == 409
    assert %{"code" => "identity_key_conflict"} = Jason.decode!(conn.resp_body)
  end

  test "a missing required field answers 422 with field errors", %{conn: conn, token: token} do
    body = Map.delete(device_body(), "platform")

    conn =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", body)

    assert conn.status == 422
    assert %{"code" => "unprocessable", "errors" => errors} = Jason.decode!(conn.resp_body)
    assert Enum.any?(errors, &(&1["path"] == "platform"))
  end

  test "invalid base64 key bytes answer 400", %{conn: conn, token: token} do
    body = device_body(%{"identity_key_public" => "not base64!"})

    conn =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", body)

    assert conn.status == 400
    assert %{"code" => "invalid_request"} = Jason.decode!(conn.resp_body)
  end

  test "unknown body fields answer 400", %{conn: conn, token: token} do
    body = Map.put(device_body(), "user_id", "0190f1e2-6d7e-7f80-b192-3d4e5f607182")

    conn =
      conn
      |> authenticated(token)
      |> json_request(:post, "/api/v1/devices", body)

    assert conn.status == 400
    assert %{"code" => "invalid_request"} = Jason.decode!(conn.resp_body)
  end

  test "lists only the authenticated user's devices", %{conn: conn, user: user, token: token} do
    own = device_fixture(%{user_id: user.id})
    _other = device_fixture()

    conn =
      conn
      |> authenticated(token)
      |> get("/api/v1/devices")

    assert conn.status == 200
    assert %{"items" => [view]} = Jason.decode!(conn.resp_body)
    assert view["device_id"] == own.id
  end

  test "revokes a device idempotently", %{conn: conn, user: user, token: token} do
    device = device_fixture(%{user_id: user.id})

    first =
      conn
      |> authenticated(token)
      |> post("/api/v1/devices/#{device.id}/revoke")

    second =
      conn
      |> authenticated(token)
      |> post("/api/v1/devices/#{device.id}/revoke")

    assert first.status == 200
    assert second.status == 200
    assert %{"status" => "revoked", "revoked_at" => revoked_at} = Jason.decode!(first.resp_body)
    assert revoked_at

    assert Jason.decode!(first.resp_body)["device_id"] ==
             Jason.decode!(second.resp_body)["device_id"]
  end

  test "does not reveal another user's device", %{conn: conn, token: token} do
    other = device_fixture()

    conn =
      conn
      |> authenticated(token)
      |> post("/api/v1/devices/#{other.id}/revoke")

    assert conn.status == 404
    assert %{"code" => "not_found"} = Jason.decode!(conn.resp_body)
  end

  test "rejects a declared body larger than 256 KiB before parsing", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> authenticated(token)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", Integer.to_string(262_145))
      |> post("/api/v1/devices", "")

    assert conn.status == 413
    assert content_type(conn) =~ "application/problem+json"
    assert %{"code" => "payload_too_large"} = Jason.decode!(conn.resp_body)
  end
end

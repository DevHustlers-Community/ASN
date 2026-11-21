defmodule AsnChatWeb.KeyPackageApiTest do
  use AsnChatWeb.ConnCase, async: true

  import AsnChat.ChatFixtures

  alias AsnChat.AuthFixtures

  setup do
    user = user_fixture()
    device = device_fixture(%{user_id: user.id})
    %{user: user, device: device, token: AuthFixtures.token(user.id)}
  end

  defp authenticated(conn, token) do
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp upload(conn, token, device, body) do
    conn
    |> authenticated(token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/devices/#{device.id}/key-packages", Jason.encode!(body))
  end

  defp body(overrides \\ %{}) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(30, :day)
      |> DateTime.to_iso8601()

    Map.merge(
      %{
        "key_package" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "ciphersuite" => 1,
        "expires_at" => expires_at
      },
      overrides
    )
  end

  defp decode(conn), do: Jason.decode!(conn.resp_body)

  test "uploads an opaque KeyPackage and returns metadata only", %{
    conn: conn,
    token: token,
    device: device
  } do
    conn = upload(conn, token, device, body(%{"last_resort" => true}))

    assert conn.status == 201
    view = decode(conn)

    assert Map.keys(view) == [
             "ciphersuite",
             "created_at",
             "device_id",
             "expires_at",
             "id",
             "last_resort"
           ]

    assert view["device_id"] == device.id
    assert String.at(view["id"], 14) == "7"
    assert view["ciphersuite"] == 1
    assert view["last_resort"] == true
    refute Map.has_key?(view, "key_package")
    refute Map.has_key?(view, "consumed_at")

    stored = AsnChat.Repo.one!(AsnChat.Devices.KeyPackage)
    assert byte_size(stored.key_package) == 64
    assert byte_size(stored.key_package_sha256) == 32
  end

  test "rejects duplicate bytes for the same device", %{conn: conn, token: token, device: device} do
    request = body()

    assert upload(conn, token, device, request).status == 201

    conn = upload(conn, token, device, request)
    assert conn.status == 409
    assert %{"code" => "conflict"} = decode(conn)
  end

  test "does not reveal a foreign device", %{conn: conn, token: token} do
    conn = upload(conn, token, device_fixture(), body())

    assert conn.status == 404
    assert %{"code" => "not_found"} = decode(conn)
  end

  test "does not accept a revoked device", %{conn: conn, token: token, device: device, user: user} do
    {:ok, _device, _result} = AsnChat.Devices.revoke_device(user.id, device.id)

    assert upload(conn, token, device, body()).status == 404
  end

  test "rejects malformed base64 and unknown fields", %{conn: conn, token: token, device: device} do
    for bad <- [
          body(%{"key_package" => "not base64!"}),
          Map.put(body(), "user_id", device.user_id)
        ] do
      response = upload(conn, token, device, bad)
      assert response.status == 400
      assert %{"code" => "invalid_request"} = decode(response)
    end
  end

  test "rejects expired and over-long lifetimes", %{conn: conn, token: token, device: device} do
    past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_iso8601()
    far = DateTime.utc_now() |> DateTime.add(91, :day) |> DateTime.to_iso8601()

    for expires_at <- [past, far] do
      response = upload(conn, token, device, body(%{"expires_at" => expires_at}))
      assert response.status == 422
      assert %{"code" => "unprocessable", "errors" => errors} = decode(response)
      assert Enum.any?(errors, &(&1["path"] == "expires_at"))
    end
  end

  test "rejects ciphersuite outside the uint16 range", %{conn: conn, token: token, device: device} do
    for ciphersuite <- [0, 65_536] do
      response = upload(conn, token, device, body(%{"ciphersuite" => ciphersuite}))
      assert response.status == 422
      assert %{"code" => "unprocessable"} = decode(response)
    end
  end

  test "lists metadata without bytes and only for the owned device", %{
    conn: conn,
    token: token,
    device: device
  } do
    assert upload(conn, token, device, body()).status == 201
    other = device_fixture()
    assert upload(conn, token, other, body()).status == 404

    conn = authenticated(conn, token) |> get("/api/v1/devices/#{device.id}/key-packages")

    assert conn.status == 200
    assert %{"items" => [view]} = decode(conn)
    assert view["device_id"] == device.id
    refute Map.has_key?(view, "key_package")
  end

  test "rejects a declared body larger than 256 KiB before parsing", %{
    conn: conn,
    token: token,
    device: device
  } do
    conn =
      conn
      |> authenticated(token)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", Integer.to_string(262_145))
      |> post("/api/v1/devices/#{device.id}/key-packages", "")

    assert conn.status == 413
    assert %{"code" => "payload_too_large"} = decode(conn)
  end
end

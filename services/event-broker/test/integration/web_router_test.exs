defmodule AsnEventBroker.Web.RouterTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Repo, Security}

  @router AsnEventBroker.Web.Router

  def issue(scopes, opts \\ []), do: Security.issue("test-service", scopes, opts)

  def call(method, path, credential_token, body \\ nil) do
    headers =
      if credential_token do
        [{"authorization", "Bearer " <> credential_token}, {"content-type", "application/json"}]
      else
        [{"content-type", "application/json"}]
      end

    body_bits = if body, do: Jason.encode!(body), else: ""

    conn =
      Plug.Test.conn(method, path, body_bits)
      |> Map.put(:req_headers, headers)

    @router.call(conn, @router.init([]))
  end

  def publish_body(event_id) do
    %{
      "event_id" => event_id,
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => "2026-10-25T10:00:00Z",
      "payload" => %{"user_id" => "u-1"}
    }
  end

  test "health endpoints need no auth" do
    assert %Plug.Conn{status: 200} = call("GET", "/healthz", nil)
    assert %Plug.Conn{status: 200} = call("GET", "/readyz", nil)
  end

  test "requests without a bearer token are rejected" do
    conn = call("POST", "/v1/events", nil, publish_body(Ecto.UUID.generate()))
    assert conn.status == 401
    assert %{"code" => "unauthorized"} = Jason.decode!(conn.resp_body)
  end

  test "publish requires the publish scope" do
    consume = issue([:consume]).token
    conn = call("POST", "/v1/events", consume, publish_body(Ecto.UUID.generate()))
    assert conn.status == 403
    assert %{"code" => "missing_scope"} = Jason.decode!(conn.resp_body)
  end

  test "publish returns 201 then 200 duplicate, then 409 on content change" do
    publisher = issue([:publish]).token
    event_id = Ecto.UUID.generate()

    assert %{status: 201} = call("POST", "/v1/events", publisher, publish_body(event_id))
    assert %{status: 200} = call("POST", "/v1/events", publisher, publish_body(event_id))
    changed = publish_body(event_id) |> Map.put("payload", %{"user_id" => "changed"})
    assert %{status: 409} = call("POST", "/v1/events", publisher, changed)

    assert %{"code" => "event_conflict"} =
             call("POST", "/v1/events", publisher, changed)
             |> Map.get(:resp_body)
             |> Jason.decode!()
  end

  test "publish rejects an invalid envelope with 400 and reused aggregate version with 422" do
    publisher = issue([:publish]).token

    assert %{status: 400} =
             call(
               "POST",
               "/v1/events",
               publisher,
               publish_body(Ecto.UUID.generate()) |> Map.put("type", "BAD")
             )

    agg = %{
      "aggregate_type" => "user",
      "aggregate_id" => Ecto.UUID.generate(),
      "aggregate_version" => 1
    }

    assert %{status: 201} =
             call(
               "POST",
               "/v1/events",
               publisher,
               publish_body(Ecto.UUID.generate()) |> Map.merge(agg)
             )

    second =
      publish_body(Ecto.UUID.generate())
      |> Map.merge(agg)
      |> Map.put("type", "user.updated")

    conn = call("POST", "/v1/events", publisher, second)
    assert conn.status == 422
    assert %{"code" => "aggregate_version_taken"} = Jason.decode!(conn.resp_body)
  end

  test "credentials restricted to event types cannot publish outside the allow-list" do
    restricted =
      Security.issue("social-api", [:publish], allowed_event_types: ["report.created"]).token

    assert %{status: 403} =
             call("POST", "/v1/events", restricted, publish_body(Ecto.UUID.generate()))

    report = publish_body(Ecto.UUID.generate()) |> Map.put("type", "report.created")
    assert %{status: 201} = call("POST", "/v1/events", restricted, report)
  end

  test "claims, ack, and nack over HTTP with lease-token rules" do
    # Seed a subscription and an event through the API itself.
    admin = issue([:publish, :consume, :admin]).token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "chat-identity",
               "consumer" => "chat-service"
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn =
      call("POST", "/v1/subscriptions/chat-identity/claims", admin, %{"max" => 10, "wait_ms" => 0})

    assert conn.status == 200

    assert [%{"delivery_id" => id, "lease_token" => token, "payload" => %{"user_id" => "u-1"}}] =
             Jason.decode!(conn.resp_body)["deliveries"]

    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{id}/ack", admin, %{"lease_token" => token})

    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{id}/ack", admin, %{"lease_token" => token})

    other = issue([:consume]).token

    assert %{status: 200} =
             call("POST", "/v1/subscriptions/chat-identity/claims", other, %{
               "max" => 10,
               "wait_ms" => 0
             })
  end

  test "paused subscriptions claim with 409" do
    admin = issue([:publish, :consume, :admin]).token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "paused-sub",
               "consumer" => "chat-service",
               "status" => "paused"
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn = call("POST", "/v1/subscriptions/paused-sub/claims", admin, %{"max" => 1})
    assert conn.status == 409
    assert %{"code" => "subscription_paused"} = Jason.decode!(conn.resp_body)
  end

  test "dead-letter skip and replay over HTTP are admin-scoped" do
    admin = issue([:publish, :consume, :admin]).token
    consumer = issue([:consume]).token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "dl-sub",
               "consumer" => "chat-service",
               "max_attempts" => 1
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn = call("POST", "/v1/subscriptions/dl-sub/claims", admin, %{"max" => 1, "wait_ms" => 0})
    assert %{"deliveries" => [delivery]} = Jason.decode!(conn.resp_body)

    # nack to dead (max_attempts = 1)
    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{delivery["delivery_id"]}/nack", admin, %{
               "lease_token" => delivery["lease_token"],
               "error_kind" => "poison"
             })

    # inspection
    conn = call("GET", "/v1/deliveries?state=dead&subscription=dl-sub", admin, nil)
    assert [%{"delivery_id" => dead_id}] = Jason.decode!(conn.resp_body)["deliveries"]

    # consume scope cannot replay
    assert %{status: 403} =
             call("POST", "/v1/dead-letters/replay", consumer, %{"delivery_id" => dead_id})

    assert %{status: 200} =
             call("POST", "/v1/dead-letters/replay", admin, %{"delivery_id" => dead_id})

    assert %{status: 409} =
             call("POST", "/v1/dead-letters/replay", admin, %{"delivery_id" => dead_id})

    # audit entries recorded
    entries = Repo.all(AsnEventBroker.Audit.AuditEntry)
    assert Enum.any?(entries, &(&1.action == "dead_letter.replay"))
  end

  test "oversized bodies are rejected with 413 before parsing" do
    publisher = issue([:publish]).token
    huge = String.duplicate("x", 300 * 1024)

    conn =
      Plug.Test.conn(
        "POST",
        "/v1/events",
        Jason.encode!(publish_body(Ecto.UUID.generate()) |> Map.put("payload", %{"blob" => huge}))
      )
      |> Map.put(:req_headers, [
        {"authorization", "Bearer " <> publisher},
        {"content-type", "application/json"},
        {"content-length", "400000"}
      ])

    conn = @router.call(conn, @router.init([]))
    assert conn.status == 413
    assert %{"code" => "payload_too_large"} = Jason.decode!(conn.resp_body)
  end

  test "unknown routes return problem details" do
    admin = issue([:admin]).token
    conn = call("GET", "/v1/nothing", admin)
    assert conn.status == 404
    assert %{"title" => "Not Found"} = Jason.decode!(conn.resp_body)
  end
end

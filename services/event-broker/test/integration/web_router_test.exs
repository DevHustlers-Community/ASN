defmodule AsnEventBroker.Web.RouterTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Repo, Security}

  @router AsnEventBroker.Web.Router

  def issue(scopes, opts \\ []) do
    service_name = Keyword.get(opts, :service_name, "test-service")
    opts = Keyword.delete(opts, :service_name)
    Security.issue(service_name, scopes, opts) |> elem(1)
  end

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
      Security.issue("social-api", [:publish], allowed_event_types: ["report.created"])
      |> elem(1)
      |> Map.fetch!(:token)

    assert %{status: 403} =
             call("POST", "/v1/events", restricted, publish_body(Ecto.UUID.generate()))

    report = publish_body(Ecto.UUID.generate()) |> Map.put("type", "report.created")
    assert %{status: 201} = call("POST", "/v1/events", restricted, report)
  end

  test "claims and ack over HTTP with lease-token rules and consumer isolation" do
    # Seed a subscription and an event through the API itself.
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "chat-identity",
               "consumer" => "chat-service"
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn =
      call("POST", "/v1/subscriptions/chat-identity/claims", consumer, %{
        "max" => 10,
        "wait_ms" => 0
      })

    assert conn.status == 200

    assert [%{"delivery_id" => id, "lease_token" => token, "payload" => %{"user_id" => "u-1"}}] =
             Jason.decode!(conn.resp_body)["deliveries"]

    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{id}/ack", consumer, %{"lease_token" => token})

    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{id}/ack", consumer, %{"lease_token" => token})

    other = issue([:consume], service_name: "other-service").token

    assert %{status: 404} =
             call("POST", "/v1/subscriptions/chat-identity/claims", other, %{
               "max" => 10,
               "wait_ms" => 0
             })
  end

  test "cross-service credentials cannot ack, nack, or extend another service's delivery" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token
    other = issue([:consume], service_name: "other-service").token
    publisher = issue([:publish], service_name: "social-api").token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "isolated-delivery",
               "consumer" => "chat-service"
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    assert %{"deliveries" => [delivery]} =
             call("POST", "/v1/subscriptions/isolated-delivery/claims", consumer, %{
               "max" => 1,
               "wait_ms" => 0
             })
             |> Map.fetch!(:resp_body)
             |> Jason.decode!()

    id = delivery["delivery_id"]
    token = delivery["lease_token"]

    for path <- ["ack", "nack", "extend"] do
      assert %{status: 404} =
               call("POST", "/v1/deliveries/#{id}/#{path}", other, %{"lease_token" => token})
    end

    assert %{status: 403} =
             call("POST", "/v1/deliveries/#{id}/ack", publisher, %{"lease_token" => token})

    row = Repo.get!(AsnEventBroker.Delivery.Delivery, id)
    assert row.state == :leased
    assert row.lease_token_hash == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{id}/extend", consumer, %{"lease_token" => token})
  end

  test "paused subscriptions claim with 409" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "paused-sub",
               "consumer" => "chat-service",
               "status" => "paused"
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn = call("POST", "/v1/subscriptions/paused-sub/claims", consumer, %{"max" => 1})
    assert conn.status == 409
    assert %{"code" => "subscription_paused"} = Jason.decode!(conn.resp_body)
  end

  test "dead-letter skip and replay over HTTP are admin-scoped" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token
    other_consumer = issue([:consume], service_name: "other-service").token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "dl-sub",
               "consumer" => "chat-service",
               "max_attempts" => 1
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn =
      call("POST", "/v1/subscriptions/dl-sub/claims", consumer, %{"max" => 1, "wait_ms" => 0})

    assert %{"deliveries" => [delivery]} = Jason.decode!(conn.resp_body)

    # nack to dead (max_attempts = 1)
    assert %{status: 200} =
             call("POST", "/v1/deliveries/#{delivery["delivery_id"]}/nack", consumer, %{
               "lease_token" => delivery["lease_token"],
               "error_kind" => "poison"
             })

    # inspection
    conn = call("GET", "/v1/deliveries?state=dead&subscription=dl-sub", admin, nil)
    assert [%{"delivery_id" => dead_id}] = Jason.decode!(conn.resp_body)["deliveries"]

    # consume scope cannot replay
    assert %{status: 403} =
             call("POST", "/v1/dead-letters/replay", consumer, %{"delivery_id" => dead_id})

    assert %{status: 404} =
             call("POST", "/v1/deliveries/#{dead_id}/ack", other_consumer, %{
               "lease_token" => delivery["lease_token"]
             })

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

  test "PATCH subscription pauses and resumes with an audit trail" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token

    assert %{status: 201, resp_body: body} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "patched",
               "consumer" => "chat-service"
             })

    assert Jason.decode!(body)["max_attempts"] == 5

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    assert %{status: 200, resp_body: body} =
             call("PATCH", "/v1/subscriptions/patched", admin, %{"status" => "paused"})

    assert Jason.decode!(body)["status"] == "paused"

    assert %{status: 409} =
             call("POST", "/v1/subscriptions/patched/claims", consumer, %{"max" => 1})

    assert %{status: 200} =
             call("PATCH", "/v1/subscriptions/patched", admin, %{"status" => "active"})

    assert %{status: 200} =
             call("POST", "/v1/subscriptions/patched/claims", consumer, %{"max" => 1})

    entries = Repo.all(AsnEventBroker.Audit.AuditEntry)
    audit_actions = Enum.map(entries, & &1.action)
    assert "subscription.create" in audit_actions
    assert "subscription.update" in audit_actions

    created =
      Enum.find(
        entries,
        &(&1.action == "subscription.create" and &1.target == "subscription:patched")
      )

    assert created.params["max_attempts"] == 5
    assert created.params["consumer"] == "chat-service"

    assert %{status: 404} =
             call("PATCH", "/v1/subscriptions/nope", admin, %{"status" => "paused"})
  end

  test "PATCH subscription can update event_types filters" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "filtered",
               "consumer" => "chat-service",
               "event_types" => ["report.created"]
             })

    assert %{status: 201} =
             call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    assert %{status: 200} =
             call("PATCH", "/v1/subscriptions/filtered", admin, %{
               "event_types" => ["user.created"]
             })

    # New filter applies from now on: deliveries are created at publish time.
    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    conn = call("POST", "/v1/subscriptions/filtered/claims", consumer, %{"max" => 10})
    assert [%{"type" => "user.created"}] = Jason.decode!(conn.resp_body)["deliveries"]
  end

  test "credential lifecycle: issue once, list without secrets, revoke blocks access" do
    admin = issue([:admin]).token

    conn =
      call("POST", "/v1/credentials", admin, %{
        "service_name" => "social-api",
        "scopes" => ["publish"]
      })

    assert conn.status == 201

    assert %{"credential_id" => credential_id, "token" => issued_token} =
             Jason.decode!(conn.resp_body)

    conn = call("GET", "/v1/credentials", admin)
    views = Jason.decode!(conn.resp_body)["credentials"]
    view = Enum.find(views, &(&1["credential_id"] == credential_id))
    assert view["service_name"] == "social-api"
    refute Map.has_key?(view, "token")
    refute Map.has_key?(view, "token_hash")

    # The issued token works, revocation stops it immediately.
    assert %{status: 403} = call("GET", "/v1/credentials", issued_token)

    revoker = issue([:admin]).token
    assert %{status: 200} = call("POST", "/v1/credentials/#{credential_id}/revoke", revoker, nil)

    assert %{status: 401} =
             call("POST", "/v1/events", issued_token, publish_body(Ecto.UUID.generate()))

    assert %{status: 404} =
             call("POST", "/v1/credentials/#{Ecto.UUID.generate()}/revoke", revoker, nil)

    audit_actions = Repo.all(AsnEventBroker.Audit.AuditEntry) |> Enum.map(& &1.action)
    assert "credential.create" in audit_actions
    assert "credential.revoke" in audit_actions
  end

  test "credential issuance persists a future expires_at" do
    admin = issue([:admin]).token
    expires_at = DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.add(3600)

    conn =
      call("POST", "/v1/credentials", admin, %{
        "service_name" => "expiring-service",
        "scopes" => ["publish"],
        "expires_at" => DateTime.to_iso8601(expires_at)
      })

    assert %{status: 201} = conn
    %{"credential_id" => credential_id, "token" => token} = Jason.decode!(conn.resp_body)

    views =
      call("GET", "/v1/credentials", admin)
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()
      |> Map.fetch!("credentials")

    view = Enum.find(views, &(&1["credential_id"] == credential_id))
    assert view["expires_at"] == DateTime.to_iso8601(expires_at)
    refute Map.has_key?(view, "token")

    assert %{status: 201} =
             call("POST", "/v1/events", token, publish_body(Ecto.UUID.generate()))
  end

  test "credential issuance rejects unknown scopes" do
    admin = issue([:admin]).token

    assert %{status: 400} =
             call("POST", "/v1/credentials", admin, %{
               "service_name" => "x",
               "scopes" => ["publish", "root"]
             })
  end

  test "publish missing or malformed type is a 400, not a 403" do
    restricted =
      Security.issue("social-api", [:publish], allowed_event_types: ["report.created"])
      |> elem(1)
      |> Map.fetch!(:token)

    # Missing type: the envelope validator's 400 wins over the allow-list.
    body = publish_body(Ecto.UUID.generate()) |> Map.delete("type")
    conn = call("POST", "/v1/events", restricted, body)
    assert conn.status == 400
    assert %{"code" => "invalid_envelope"} = Jason.decode!(conn.resp_body)

    # Structurally invalid type: also 400.
    body = publish_body(Ecto.UUID.generate()) |> Map.put("type", "Not.AnEvent")
    conn = call("POST", "/v1/events", restricted, body)
    assert conn.status == 400
    assert %{"code" => "invalid_envelope"} = Jason.decode!(conn.resp_body)

    # Structurally valid but unlisted: 403.
    conn = call("POST", "/v1/events", restricted, publish_body(Ecto.UUID.generate()))
    assert conn.status == 403
    assert %{"code" => "event_type_forbidden"} = Jason.decode!(conn.resp_body)
  end

  test "claim max and delivery limit reject malformed or out-of-range values" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "bounds-sub",
               "consumer" => "chat-service"
             })

    for bad_max <- ["abc", 0] do
      conn =
        call("POST", "/v1/subscriptions/bounds-sub/claims", consumer, %{
          "max" => bad_max,
          "wait_ms" => 0
        })

      assert conn.status == 400
      assert %{"code" => "invalid_request"} = Jason.decode!(conn.resp_body)
    end

    for bad_limit <- ["201", 0, "abc"] do
      conn = call("GET", "/v1/deliveries?state=dead&limit=#{bad_limit}", admin, nil)
      assert conn.status == 400
      assert %{"code" => "invalid_request"} = Jason.decode!(conn.resp_body)
    end

    assert %{status: 200} = call("GET", "/v1/deliveries?state=dead&limit=200", admin, nil)
  end

  test "ack and nack reject malformed ids and missing lease tokens without crashing" do
    admin = issue([:publish, :admin]).token
    consumer = issue([:consume], service_name: "chat-service").token

    conn = call("POST", "/v1/deliveries/not-a-uuid/ack", consumer, %{"lease_token" => "token"})
    assert conn.status == 404
    assert %{"code" => "not_found"} = Jason.decode!(conn.resp_body)

    conn = call("POST", "/v1/deliveries/not-a-uuid/nack", consumer, %{"lease_token" => "token"})
    assert conn.status == 404

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "missing-token",
               "consumer" => "chat-service"
             })

    assert %{status: 201} = call("POST", "/v1/events", admin, publish_body(Ecto.UUID.generate()))

    assert %{"deliveries" => [delivery]} =
             call("POST", "/v1/subscriptions/missing-token/claims", consumer, %{
               "max" => 1,
               "wait_ms" => 0
             })
             |> Map.fetch!(:resp_body)
             |> Jason.decode!()

    id = delivery["delivery_id"]

    conn = call("POST", "/v1/deliveries/#{id}/ack", consumer, %{})
    assert conn.status == 400
    assert %{"code" => "invalid_request"} = Jason.decode!(conn.resp_body)

    conn = call("POST", "/v1/deliveries/#{id}/extend", consumer, %{})
    assert conn.status == 400
  end

  test "replay with a missing or malformed delivery_id is a 400" do
    admin = issue([:admin]).token

    for body <- [%{"delivery_id" => nil}, %{}, %{"delivery_id" => "nope"}] do
      conn = call("POST", "/v1/dead-letters/replay", admin, body)
      assert conn.status == 400
      assert %{"code" => "invalid_request"} = Jason.decode!(conn.resp_body)
    end
  end

  test "credential issuance rejects invalid names, allow-lists, scopes, and expiry" do
    admin = issue([:admin]).token

    for body <- [
          %{"service_name" => "", "scopes" => ["publish"]},
          %{"service_name" => "social-api", "scopes" => ["publish"], "allowed_event_types" => []},
          %{
            "service_name" => "social-api",
            "scopes" => ["publish"],
            "allowed_event_types" => ["NOT.A.TYPE"]
          },
          %{
            "service_name" => "social-api",
            "scopes" => ["publish"],
            "expires_at" => DateTime.to_iso8601(DateTime.utc_now() |> DateTime.add(-60))
          },
          %{
            "service_name" => "social-api",
            "scopes" => ["publish"],
            "expires_at" => "not-a-timestamp"
          }
        ] do
      conn = call("POST", "/v1/credentials", admin, body)
      assert conn.status == 400
      assert %{"code" => "invalid_credential"} = Jason.decode!(conn.resp_body)
    end
  end

  test "subscriptions reject an explicit null max_attempts with 409" do
    admin = issue([:admin]).token

    assert %{status: 201} =
             call("POST", "/v1/subscriptions", admin, %{
               "name" => "null-budget",
               "consumer" => "chat-service"
             })

    conn =
      call("POST", "/v1/subscriptions", admin, %{
        "name" => "null-budget-2",
        "consumer" => "chat-service",
        "max_attempts" => nil
      })

    assert conn.status == 409
    assert %{"code" => "subscription_rejected"} = Jason.decode!(conn.resp_body)

    conn = call("PATCH", "/v1/subscriptions/null-budget", admin, %{"max_attempts" => nil})
    assert conn.status == 409
    assert %{"code" => "subscription_rejected"} = Jason.decode!(conn.resp_body)
  end

  test "unknown routes return problem details" do
    admin = issue([:admin]).token
    conn = call("GET", "/v1/nothing", admin)
    assert conn.status == 404
    assert %{"title" => "Not Found"} = Jason.decode!(conn.resp_body)
  end
end

defmodule AsnEventBroker.Web.MetricsTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Acknowledgements, DeadLetter, Delivery, Publishing, Repo}
  alias AsnEventBroker.Subscriptions.Subscription

  # Unique per run so concurrent test modules never collide on the shared
  # global metrics table.
  @event_type "metrics.event.ev#{System.unique_integer([:positive])}"

  test "counter series appear after telemetry events and survive scrapes" do
    %Subscription{}
    |> Subscription.changeset(%{
      id: Ecto.UUID.generate(),
      name: "metrics-sub-#{System.unique_integer([:positive])}",
      consumer: "chat-service"
    })
    |> Repo.insert!()

    assert {:ok, :created} =
             Publishing.publish(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "type" => @event_type,
                 "schema_version" => 1,
                 "occurred_at" => "2026-10-26T10:00:00Z",
                 "payload" => %{}
               },
               "metrics-service"
             )

    body = AsnEventBroker.Web.Metrics.render()
    assert body =~ "# TYPE asn_event_broker_publish_accepted_total counter"

    assert body =~
             ~s(asn_event_broker_publish_accepted_total{type="#{@event_type}",outcome="created"} 1)
  end

  test "delivery transition and rejection counters appear" do
    name = "metrics-transitions-#{System.unique_integer([:positive])}"
    event_type = "metrics.transition.ev#{System.unique_integer([:positive])}"

    %Subscription{}
    |> Subscription.changeset(%{
      id: Ecto.UUID.generate(),
      name: name,
      consumer: "chat-service",
      event_types: [event_type],
      max_attempts: 1
    })
    |> Repo.insert!()

    assert {:error, {:invalid_envelope, _}} =
             Publishing.publish(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "type" => event_type,
                 "schema_version" => 1,
                 "occurred_at" => "not-a-timestamp",
                 "payload" => %{}
               },
               "metrics-service"
             )

    Enum.each(1..2, fn _ ->
      assert {:ok, :created} =
               Publishing.publish(
                 %{
                   "event_id" => Ecto.UUID.generate(),
                   "type" => event_type,
                   "schema_version" => 1,
                   "occurred_at" => "2026-10-26T10:00:00Z",
                   "payload" => %{}
                 },
                 "metrics-service"
               )
    end)

    assert {:ok, [first, second]} = Delivery.claim(name, 10, 0)

    assert {:ok, :dead} =
             Acknowledgements.nack(first.delivery_id, first.lease_token, "timeout")

    assert {:ok, :dead} =
             Acknowledgements.nack(second.delivery_id, second.lease_token, "timeout")

    actor = Ecto.UUID.generate()
    assert {:ok, :replayed} = DeadLetter.replay(first.delivery_id, actor)
    assert {:ok, :skipped} = DeadLetter.skip(second.delivery_id, actor)

    body = AsnEventBroker.Web.Metrics.render()

    assert body =~ "# TYPE asn_event_broker_nacks_total counter"
    assert body =~ "asn_event_broker_nacks_total{} "
    assert body =~ "# TYPE asn_event_broker_replays_total counter"
    assert body =~ "asn_event_broker_replays_total{} "
    assert body =~ "# TYPE asn_event_broker_skips_total counter"
    assert body =~ "asn_event_broker_skips_total{} "
    assert body =~ "# TYPE asn_event_broker_publish_rejected_total counter"

    assert body =~
             ~s(asn_event_broker_publish_rejected_total{reason="invalid_envelope"} )
  end

  test "gauge series reflect database state" do
    body = AsnEventBroker.Web.Metrics.render()
    assert body =~ "# TYPE asn_event_broker_pending gauge"
    assert body =~ "asn_event_broker_pending "
    assert body =~ "# TYPE asn_event_broker_oldest_pending_seconds gauge"
  end

  test "/metrics serves the exposition without authentication" do
    conn =
      Plug.Test.conn("GET", "/metrics", "")
      |> Map.put(:req_headers, [])

    conn = AsnEventBroker.Web.Router.call(conn, AsnEventBroker.Web.Router.init([]))
    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
  end
end

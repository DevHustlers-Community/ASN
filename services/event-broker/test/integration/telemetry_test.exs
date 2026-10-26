defmodule AsnEventBroker.TelemetryTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Publishing, Repo}
  alias AsnEventBroker.Subscriptions.Subscription

  setup do
    test_pid = self()

    handler_id = "test-handler-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:asn_event_broker, :publish, :accepted],
        [:asn_event_broker, :publish, :rejected],
        [:asn_event_broker, :claim]
      ],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  def insert_subscription(name) do
    %Subscription{}
    |> Subscription.changeset(%{id: Ecto.UUID.generate(), name: name, consumer: "chat-service"})
    |> Repo.insert!()
  end

  test "accepted publish emits accepted with the event type and outcome" do
    insert_subscription("chat-identity")

    event_id = Ecto.UUID.generate()

    assert {:ok, :created} =
             Publishing.publish(
               %{
                 "event_id" => event_id,
                 "type" => "user.created",
                 "schema_version" => 1,
                 "occurred_at" => "2026-10-25T10:00:00Z",
                 "payload" => %{}
               },
               "social-api"
             )

    assert_receive {:telemetry, [:asn_event_broker, :publish, :accepted], %{count: 1},
                    %{type: "user.created", outcome: :created}}

    assert {:ok, :duplicate} =
             Publishing.publish(
               %{
                 "event_id" => event_id,
                 "type" => "user.created",
                 "schema_version" => 1,
                 "occurred_at" => "2026-10-25T10:00:00Z",
                 "payload" => %{}
               },
               "social-api"
             )

    assert_receive {:telemetry, [:asn_event_broker, :publish, :accepted], _,
                    %{outcome: :duplicate}}
  end

  test "aggregate version conflicts emit rejected" do
    insert_subscription("chat-identity")

    agg = %{
      "aggregate_type" => "user",
      "aggregate_id" => Ecto.UUID.generate(),
      "aggregate_version" => 1
    }

    base = %{
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => "2026-10-25T10:00:00Z",
      "payload" => %{}
    }

    assert {:ok, :created} =
             Publishing.publish(
               Map.merge(base, Map.merge(agg, %{"event_id" => Ecto.UUID.generate()})),
               "social-api"
             )

    assert {:error, :aggregate_version_taken} =
             Publishing.publish(
               Map.merge(
                 base,
                 Map.merge(agg, %{"event_id" => Ecto.UUID.generate(), "type" => "user.updated"})
               ),
               "social-api"
             )

    assert_receive {:telemetry, [:asn_event_broker, :publish, :rejected], %{count: 1},
                    %{reason: :aggregate_version_taken}}
  end

  test "claims emit their count, including empty claims" do
    insert_subscription("empty-sub")
    assert {:ok, []} = AsnEventBroker.Delivery.claim("empty-sub", 10, 0)

    assert_receive {:telemetry, [:asn_event_broker, :claim], %{count: 0},
                    %{subscription: "empty-sub"}}
  end
end

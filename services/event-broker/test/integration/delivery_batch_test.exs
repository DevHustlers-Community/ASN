defmodule AsnEventBroker.DeliveryBatchTest do
  # This module raises the in-flight cap, which is global application
  # configuration, so it must not run concurrently with the other delivery
  # tests (which assert against the default cap of 10).
  use AsnEventBroker.DataCase, async: false

  alias AsnEventBroker.{Acknowledgements, Delivery, Publishing, Repo}
  alias AsnEventBroker.Subscriptions.Subscription

  setup do
    previous = Application.fetch_env!(:asn_event_broker, :delivery)
    Application.put_env(:asn_event_broker, :delivery, Keyword.put(previous, :max_in_flight, 100))
    on_exit(fn -> Application.put_env(:asn_event_broker, :delivery, previous) end)
    :ok
  end

  test "a max=100 claim returns a full batch when the backlog allows it" do
    insert_subscription("chat-batch-full")
    publish_aggregate_less(150)

    assert {:ok, first} = Delivery.claim("chat-batch-full", 100, 0)
    assert length(first) == 100
    assert first |> Enum.map(& &1.delivery_id) |> Enum.uniq() |> length() == 100
    assert first |> Enum.map(& &1.lease_token) |> Enum.uniq() |> length() == 100

    # 100 leases are in flight, so the cap blocks another batch.
    assert {:ok, []} = Delivery.claim("chat-batch-full", 100, 0)

    Enum.each(first, &Acknowledgements.ack(&1.delivery_id, &1.lease_token))

    assert {:ok, rest} = Delivery.claim("chat-batch-full", 100, 0)
    assert length(rest) == 50

    assert MapSet.disjoint?(
             MapSet.new(first, & &1.delivery_id),
             MapSet.new(rest, & &1.delivery_id)
           )
  end

  test "a full batch never leases two versions of one aggregate" do
    insert_subscription("chat-batch-ordered")

    for _ <- 1..100 do
      aggregate_id = Ecto.UUID.generate()

      for version <- [1, 2] do
        attrs = %{
          "event_id" => Ecto.UUID.generate(),
          "type" => "user.updated",
          "schema_version" => 1,
          "occurred_at" => "2026-10-25T10:00:00Z",
          "aggregate_type" => "user",
          "aggregate_id" => aggregate_id,
          "aggregate_version" => version,
          "payload" => %{"version" => version}
        }

        assert {:ok, :created} = Publishing.publish(attrs, "social-api")
      end
    end

    assert {:ok, first} = Delivery.claim("chat-batch-ordered", 100, 0)
    assert length(first) == 100
    assert Enum.all?(first, &(&1.aggregate_version == 1))
    assert first |> Enum.map(& &1.aggregate_id) |> Enum.uniq() |> length() == 100

    Enum.each(first, &Acknowledgements.ack(&1.delivery_id, &1.lease_token))

    assert {:ok, second} = Delivery.claim("chat-batch-ordered", 100, 0)
    assert length(second) == 100
    assert Enum.all?(second, &(&1.aggregate_version == 2))
  end

  defp insert_subscription(name) do
    %Subscription{}
    |> Subscription.changeset(%{
      id: Ecto.UUID.generate(),
      name: name,
      consumer: "chat-service",
      status: :active,
      max_attempts: 5
    })
    |> Repo.insert!()
  end

  defp publish_aggregate_less(count) do
    Enum.each(1..count, fn _ ->
      attrs = %{
        "event_id" => Ecto.UUID.generate(),
        "type" => "system.pulse",
        "schema_version" => 1,
        "occurred_at" => "2026-10-25T10:00:00Z",
        "payload" => %{}
      }

      assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    end)
  end
end

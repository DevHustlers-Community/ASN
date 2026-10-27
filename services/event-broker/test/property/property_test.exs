defmodule AsnEventBroker.PropertyTest do
  @moduledoc """
  Property-based tests for the concurrency-critical paths (external review
  recommendation): envelope validation invariants, claim ordering, and the
  one-lease-per-aggregate invariant under concurrent claimers.
  """

  use AsnEventBroker.DataCase, async: true

  import ExUnitProperties
  import StreamData

  alias AsnEventBroker.{Delivery, Publishing, Repo}
  alias AsnEventBroker.Events.Envelope
  alias AsnEventBroker.Subscriptions.Subscription

  property "valid envelopes always validate and hash deterministically" do
    check all(
            version <- integer(1..1_000),
            body <-
              map_of(
                string(:alphanumeric, min_length: 1, max_length: 8),
                one_of([integer(0..1_000), string(:alphanumeric, max_length: 12)]),
                max_length: 8
              ),
            max_runs: 25
          ) do
      attrs = %{
        "event_id" => AsnEventBroker.UUIDv7.generate(),
        "type" => "user.created",
        "schema_version" => 1,
        "occurred_at" => "2026-10-25T10:00:00Z",
        "aggregate_type" => "user",
        "aggregate_id" => AsnEventBroker.UUIDv7.generate(),
        "aggregate_version" => version,
        "payload" => body
      }

      assert {:ok, %Envelope{} = envelope} = Envelope.validate(attrs)
      hash = Envelope.content_hash(envelope)
      assert String.length(hash) == 64
      assert {:ok, envelope2} = Envelope.validate(attrs)
      assert Envelope.content_hash(envelope2) == hash
    end
  end

  property "N versions of one aggregate are leased strictly in version order" do
    check all(
            versions <- shuffle(Enum.to_list(1..6)),
            max_runs: 10
          ) do
      aggregate_id = AsnEventBroker.UUIDv7.generate()

      subscription =
        %Subscription{}
        |> Subscription.changeset(%{
          id: Ecto.UUID.generate(),
          name: "prop-#{System.unique_integer()}",
          consumer: "chat-service"
        })
        |> Repo.insert!()

      # Publish out of order would be a producer violation, so the relay has
      # already ordered them; here we verify the claim side only.
      for v <- Enum.sort(versions) do
        attrs = %{
          "event_id" => Ecto.UUID.generate(),
          "type" => "user.updated",
          "schema_version" => 1,
          "occurred_at" => "2026-10-25T10:00:00Z",
          "aggregate_type" => "user",
          "aggregate_id" => aggregate_id,
          "aggregate_version" => v,
          "payload" => %{"v" => v}
        }

        assert {:ok, :created} = Publishing.publish(attrs, "social-api")
      end

      for expected <- Enum.sort(versions) do
        assert {:ok, [claimed]} = Delivery.claim(subscription.name, 10, 0)
        assert claimed.aggregate_version == expected
        assert :ok = AsnEventBroker.Acknowledgements.ack(claimed.delivery_id, claimed.lease_token)
      end

      assert {:ok, []} = Delivery.claim(subscription.name, 10, 0)
    end
  end

  property "concurrent claimers lease at most one delivery per aggregate" do
    check all(
            claimers <- integer(2..6),
            max_runs: 10
          ) do
      subscription =
        %Subscription{}
        |> Subscription.changeset(%{
          id: Ecto.UUID.generate(),
          name: "prop-conc-#{System.unique_integer()}",
          consumer: "chat-service"
        })
        |> Repo.insert!()

      aggregate_id = AsnEventBroker.UUIDv7.generate()

      attrs = %{
        "event_id" => Ecto.UUID.generate(),
        "type" => "user.created",
        "schema_version" => 1,
        "occurred_at" => "2026-10-25T10:00:00Z",
        "aggregate_type" => "user",
        "aggregate_id" => aggregate_id,
        "aggregate_version" => 1,
        "payload" => %{}
      }

      assert {:ok, :created} = Publishing.publish(attrs, "social-api")

      parent = self()

      tasks =
        for _ <- 1..claimers do
          Task.async(fn ->
            receive do
              :go -> Delivery.claim(subscription.name, 10, 0)
            end
          end)
        end

      Enum.each(tasks, &Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, &1.pid))
      Enum.each(tasks, &send(&1.pid, :go))

      results = Task.await_many(tasks)
      leased = Enum.flat_map(results, fn {:ok, deliveries} -> deliveries end)
      assert length(leased) <= 1
    end
  end
end

defmodule AsnChat.Events.OutboxTest do
  use AsnChat.DataCase, async: true

  alias AsnChat.Events.{Envelope, Outbox}
  alias AsnChat.UUIDv7

  @aggregate_id "01912345-6789-7000-8000-0000000000aa"
  @other_aggregate_id "01912345-6789-7000-8000-0000000000bb"

  defp envelope(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => UUIDv7.generate(),
        "type" => "chat.device.registered",
        "schema_version" => 1,
        "occurred_at" => "2026-10-26T10:00:00Z",
        "payload" => %{"device_id" => "d-1"}
      },
      overrides
    )
  end

  defp aggregate(overrides \\ %{}) do
    Map.merge(
      %{
        "aggregate_type" => "device",
        "aggregate_id" => @aggregate_id,
        "aggregate_version" => 1
      },
      overrides
    )
  end

  defp record!(overrides) do
    {:ok, row} = Outbox.record(envelope(overrides))
    row
  end

  describe "record/1" do
    test "stores the envelope as typed columns with the event id as the row id" do
      env =
        envelope(%{
          "type" => "chat.conversation.created",
          "schema_version" => 2,
          "occurred_at" => "2026-10-26T12:30:45.123456+02:00",
          "trace_id" => "4bf92f3577b34da6a3ce929d0e0e4736",
          "payload" => %{"conversation_id" => @aggregate_id, "kind" => "direct"}
        })
        |> Map.merge(aggregate(%{"aggregate_type" => "conversation", "aggregate_version" => 9}))

      assert {:ok, row} = Outbox.record(env)

      assert row.id == env["event_id"]
      assert row.type == "chat.conversation.created"
      assert row.schema_version == 2
      assert row.occurred_at == ~U[2026-10-26 10:30:45.123456Z]
      assert row.aggregate_type == "conversation"
      assert row.aggregate_id == @aggregate_id
      assert row.aggregate_version == 9
      assert row.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
      assert row.payload == %{"conversation_id" => @aggregate_id, "kind" => "direct"}
      assert is_nil(row.published_at)
      assert %DateTime{} = row.created_at

      persisted = Repo.get!(Outbox, row.id)
      assert persisted == row
    end

    test "stores events without an aggregate or trace id" do
      row = record!(%{})

      assert is_nil(row.aggregate_type)
      assert is_nil(row.aggregate_id)
      assert is_nil(row.aggregate_version)
      assert is_nil(row.trace_id)
      assert row.payload == %{"device_id" => "d-1"}
    end

    test "normalizes offset timestamps to UTC microseconds" do
      row = record!(%{"occurred_at" => "2026-10-26T12:00:00+02:00"})
      assert row.occurred_at == ~U[2026-10-26 10:00:00.000000Z]
      assert Repo.get!(Outbox, row.id).occurred_at == ~U[2026-10-26 10:00:00.000000Z]
    end

    test "treats an empty trace id as absent" do
      row = record!(%{"trace_id" => ""})
      assert is_nil(row.trace_id)
    end

    test "accepts an empty payload object" do
      row = record!(%{"payload" => %{}})
      assert row.payload == %{}
    end

    test "requires the event id, type, schema version, occurred_at, and payload" do
      for field <- ~w(event_id type schema_version occurred_at payload) do
        env = Map.delete(envelope(), field)

        assert {:error, changeset} = Outbox.record(env)

        assert changeset.errors[String.to_atom(field)],
               "expected an error for missing #{field}, got: #{inspect(changeset.errors)}"
      end
    end

    test "rejects a malformed event id" do
      assert {:error, changeset} = Outbox.record(envelope(%{"event_id" => "not-a-uuid"}))
      assert {"is invalid", _} = changeset.errors[:id]
    end

    test "rejects a malformed event type" do
      assert {:error, changeset} = Outbox.record(envelope(%{"type" => "Chat Device"}))
      assert changeset.errors[:type]
    end

    test "rejects a malformed aggregate type" do
      assert {:error, changeset} =
               Outbox.record(envelope(aggregate(%{"aggregate_type" => "not a type"})))

      assert changeset.errors[:aggregate_type]
    end

    test "rejects schema versions below one" do
      assert {:error, changeset} = Outbox.record(envelope(%{"schema_version" => 0}))
      assert changeset.errors[:schema_version]
    end

    test "rejects aggregate versions below one" do
      assert {:error, changeset} =
               Outbox.record(envelope(aggregate(%{"aggregate_version" => 0})))

      assert changeset.errors[:aggregate_version]
    end

    test "requires aggregate fields to be all present or all absent" do
      for field <- ~w(aggregate_type aggregate_id aggregate_version) do
        assert {:error, changeset} =
                 Outbox.record(envelope(Map.delete(aggregate(), field)))

        assert changeset.errors[:aggregate_type],
               "expected an aggregate mismatch error, got: #{inspect(changeset.errors)}"
      end
    end

    test "rejects a non-object payload" do
      assert {:error, changeset} =
               Outbox.record(envelope(%{"payload" => ["not", "an", "object"]}))

      assert changeset.errors[:payload]
    end

    test "rejects unknown envelope fields" do
      assert {:error, changeset} = Outbox.record(envelope(%{"device_label" => "leak"}))
      assert {"envelope contains unknown fields: \"device_label\"", _} = changeset.errors[:base]
    end

    test "rejects a duplicate event id" do
      row = record!(%{})

      assert {:error, changeset} = Outbox.record(envelope(%{"event_id" => row.id}))
      assert {"has already been taken", _} = changeset.errors[:id]
    end

    test "rejects a reused aggregate version before it reaches the broker" do
      record!(aggregate(%{"aggregate_version" => 4}))

      assert {:error, changeset} =
               Outbox.record(envelope(aggregate(%{"aggregate_version" => 4})))

      assert {"has already been taken", _} = changeset.errors[:aggregate_version]
    end

    test "allows the same aggregate version for a different aggregate id" do
      record!(aggregate(%{"aggregate_version" => 4}))
      row = record!(aggregate(%{"aggregate_id" => @other_aggregate_id, "aggregate_version" => 4}))
      assert row.aggregate_version == 4
    end

    test "a rolled-back transaction leaves no outbox row" do
      assert_raise RuntimeError, "business failure", fn ->
        Repo.transaction(fn ->
          {:ok, _row} = Outbox.record(envelope())
          raise "business failure"
        end)
      end

      assert Outbox.unpublished() == []
    end
  end

  describe "unpublished/1" do
    test "orders by aggregate then version" do
      b1 = record!(aggregate(%{"aggregate_id" => @other_aggregate_id, "aggregate_version" => 1}))
      a2 = record!(aggregate(%{"aggregate_version" => 2}))
      a1 = record!(aggregate(%{"aggregate_version" => 1}))
      a3 = record!(aggregate(%{"aggregate_version" => 3}))

      assert Enum.map(Outbox.unpublished(), & &1.id) == [a1.id, a2.id, a3.id, b1.id]
    end

    test "excludes published rows" do
      first = record!(%{})
      second = record!(%{})

      assert :ok = Outbox.mark_published(first.id)

      assert Enum.map(Outbox.unpublished(), & &1.id) == [second.id]
      assert Repo.get!(Outbox, first.id).published_at
      assert is_nil(Repo.get!(Outbox, second.id).published_at)
    end

    test "mark_published is idempotent" do
      row = record!(%{})

      assert :ok = Outbox.mark_published(row.id)
      published_at = Repo.get!(Outbox, row.id).published_at

      assert :ok = Outbox.mark_published(row.id)
      assert Repo.get!(Outbox, row.id).published_at == published_at
      assert Outbox.unpublished() == []
    end

    test "respects the limit" do
      record!(%{})
      record!(%{})
      record!(%{})

      assert length(Outbox.unpublished(2)) == 2
    end
  end

  describe "database invariants" do
    test "the schema_version check rejects zero" do
      error = assert_raise Postgrex.Error, fn -> raw_insert!(%{schema_version: 0}) end
      assert error.postgres.constraint == "outbox_events_schema_version_check"
    end

    test "the aggregate fields check rejects a partial aggregate" do
      error =
        assert_raise Postgrex.Error, fn ->
          raw_insert!(%{aggregate_type: "device", aggregate_id: @aggregate_id})
        end

      assert error.postgres.constraint == "outbox_events_aggregate_fields_check"
    end

    test "the aggregate version check rejects zero" do
      error =
        assert_raise Postgrex.Error, fn ->
          raw_insert!(%{
            aggregate_type: "device",
            aggregate_id: @aggregate_id,
            aggregate_version: 0
          })
        end

      assert error.postgres.constraint == "outbox_events_aggregate_version_check"
    end

    test "the payload check rejects a JSON array" do
      error = assert_raise Postgrex.Error, fn -> raw_insert!(%{payload_json: "[1,2]"}) end
      assert error.postgres.constraint == "outbox_events_payload_object_check"
    end

    test "the partial unique index rejects a duplicate aggregate version" do
      raw_insert!(%{
        aggregate_type: "device",
        aggregate_id: @aggregate_id,
        aggregate_version: 1
      })

      error =
        assert_raise Postgrex.Error, fn ->
          raw_insert!(%{
            aggregate_type: "device",
            aggregate_id: @aggregate_id,
            aggregate_version: 1
          })
        end

      assert error.postgres.constraint == "outbox_events_aggregate_version_unique_index"
    end
  end

  describe "envelope round trip" do
    test "rebuilding a stored row preserves the broker's canonical content" do
      env =
        envelope(%{
          "occurred_at" => "2026-10-26T10:00:00Z",
          "trace_id" => "4bf92f3577b34da6a3ce929d0e0e4736",
          "payload" => %{"nested" => %{"b" => 2, "a" => [1, 2, 3]}}
        })
        |> Map.merge(aggregate(%{"aggregate_version" => 11}))

      row = record!(env)
      persisted = Repo.get!(Outbox, row.id)
      rebuilt = Envelope.from_outbox(persisted)

      assert broker_canonical(env) == broker_canonical(rebuilt)
    end

    test "rebuilding an envelope without optional fields preserves canonical content" do
      env = envelope(%{"payload" => %{"z" => 1, "a" => %{"b" => true}}})
      row = record!(env)
      rebuilt = Envelope.from_outbox(Repo.get!(Outbox, row.id))

      assert rebuilt["occurred_at"] == "2026-10-26T10:00:00.000000Z"
      assert broker_canonical(env) == broker_canonical(rebuilt)
    end
  end

  # Mirrors the broker's content_hash input: every envelope field is present
  # (nil when absent), occurred_at is normalized to microseconds, keys are
  # recursively sorted, then the canonical JSON is hashed.
  defp broker_canonical(envelope) do
    %{
      "event_id" => envelope["event_id"],
      "type" => envelope["type"],
      "schema_version" => envelope["schema_version"],
      "occurred_at" => normalize_timestamp(envelope["occurred_at"]),
      "aggregate_type" => envelope["aggregate_type"],
      "aggregate_id" => envelope["aggregate_id"],
      "aggregate_version" => envelope["aggregate_version"],
      "trace_id" => envelope["trace_id"],
      "payload" => envelope["payload"]
    }
    |> sort_keys()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp normalize_timestamp(timestamp) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(timestamp)
    %{microsecond: {microseconds, _precision}} = datetime
    DateTime.to_iso8601(%{datetime | microsecond: {microseconds, 6}})
  end

  defp sort_keys(%{} = map) do
    %Jason.OrderedObject{
      values:
        map |> Enum.map(fn {key, value} -> {to_string(key), sort_keys(value)} end) |> Enum.sort()
    }
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(value), do: value

  defp raw_insert!(overrides) do
    attrs =
      Map.merge(
        %{
          id: UUIDv7.generate(),
          type: "chat.device.registered",
          schema_version: 1,
          occurred_at: ~N[2026-10-26 10:00:00.000000],
          aggregate_type: nil,
          aggregate_id: nil,
          aggregate_version: nil,
          trace_id: nil,
          payload_json: "{}",
          created_at: ~N[2026-10-26 10:00:00.000000]
        },
        overrides
      )

    Repo.query!(
      """
      INSERT INTO outbox_events
        (id, type, schema_version, occurred_at, aggregate_type, aggregate_id,
         aggregate_version, trace_id, payload, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::text::jsonb, $10)
      """,
      [
        Ecto.UUID.dump!(attrs.id),
        attrs.type,
        attrs.schema_version,
        attrs.occurred_at,
        attrs.aggregate_type,
        attrs.aggregate_id && Ecto.UUID.dump!(attrs.aggregate_id),
        attrs.aggregate_version,
        attrs.trace_id,
        attrs.payload_json,
        attrs.created_at
      ]
    )
  end
end

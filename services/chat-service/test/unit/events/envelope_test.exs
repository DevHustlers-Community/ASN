defmodule AsnChat.Events.EnvelopeTest do
  use ExUnit.Case, async: true

  alias AsnChat.Events.Envelope

  @event_id "01912345-6789-7000-8000-0000000000aa"
  @aggregate_id "01912345-6789-7000-8000-0000000000bb"

  defp row(overrides \\ %{}) do
    Map.merge(
      %{
        id: @event_id,
        type: "chat.device.registered",
        schema_version: 1,
        occurred_at: ~U[2026-10-26 10:00:00.000000Z],
        aggregate_type: nil,
        aggregate_id: nil,
        aggregate_version: nil,
        trace_id: nil,
        payload: %{"device_id" => "d-1"}
      },
      overrides
    )
  end

  test "rebuilds every stored field" do
    row =
      row(%{
        aggregate_type: "device",
        aggregate_id: @aggregate_id,
        aggregate_version: 3,
        trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
        payload: %{"device_id" => "d-1", "fingerprint" => "fp-1"}
      })

    assert Envelope.from_outbox(row) == %{
             "event_id" => @event_id,
             "type" => "chat.device.registered",
             "schema_version" => 1,
             "occurred_at" => "2026-10-26T10:00:00.000000Z",
             "aggregate_type" => "device",
             "aggregate_id" => @aggregate_id,
             "aggregate_version" => 3,
             "trace_id" => "4bf92f3577b34da6a3ce929d0e0e4736",
             "payload" => %{"device_id" => "d-1", "fingerprint" => "fp-1"}
           }
  end

  test "omits nullable aggregate and trace fields instead of emitting nulls" do
    envelope = Envelope.from_outbox(row())

    refute Map.has_key?(envelope, "aggregate_type")
    refute Map.has_key?(envelope, "aggregate_id")
    refute Map.has_key?(envelope, "aggregate_version")
    refute Map.has_key?(envelope, "trace_id")

    assert Map.keys(envelope) |> Enum.sort() ==
             ~w(event_id occurred_at payload schema_version type)
  end

  test "keeps aggregate fields and omits only the absent trace id" do
    envelope =
      Envelope.from_outbox(
        row(%{
          aggregate_type: "conversation",
          aggregate_id: @aggregate_id,
          aggregate_version: 7
        })
      )

    assert envelope["aggregate_type"] == "conversation"
    assert envelope["aggregate_id"] == @aggregate_id
    assert envelope["aggregate_version"] == 7
    refute Map.has_key?(envelope, "trace_id")
  end

  test "renders whole seconds at microsecond precision" do
    envelope = Envelope.from_outbox(row(%{occurred_at: ~U[2026-10-26 10:00:00Z]}))
    assert envelope["occurred_at"] == "2026-10-26T10:00:00.000000Z"
  end

  test "preserves sub-second precision" do
    envelope = Envelope.from_outbox(row(%{occurred_at: ~U[2026-10-26 10:00:00.123456Z]}))
    assert envelope["occurred_at"] == "2026-10-26T10:00:00.123456Z"
  end

  test "forces six-digit precision on a lower-precision timestamp" do
    occurred_at = %{~U[2026-10-26 10:00:00Z] | microsecond: {123, 3}}
    envelope = Envelope.from_outbox(row(%{occurred_at: occurred_at}))
    assert envelope["occurred_at"] == "2026-10-26T10:00:00.000123Z"
  end

  test "passes the payload through without rewriting it" do
    payload = %{"nested" => %{"list" => [1, "two", true, nil]}}
    envelope = Envelope.from_outbox(row(%{payload: payload}))
    assert envelope["payload"] === payload
  end
end

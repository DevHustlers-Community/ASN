defmodule AsnEventBroker.Events.EnvelopeTest do
  use ExUnit.Case, async: true

  alias AsnEventBroker.Events.Envelope

  @occurred_at "2026-10-25T10:00:00+02:00"

  def valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => "01912345-6789-7000-8000-000000000001",
        "type" => "user.created",
        "schema_version" => 1,
        "occurred_at" => @occurred_at,
        "payload" => %{"user_id" => "01912345-6789-7000-8000-000000000002"}
      },
      overrides
    )
  end

  describe "validate/1" do
    test "accepts a minimal envelope and normalizes occurred_at to UTC" do
      assert {:ok, envelope} = Envelope.validate(valid_attrs())
      assert envelope.event_id == "01912345-6789-7000-8000-000000000001"
      assert DateTime.diff(envelope.occurred_at, ~U[2026-10-25 08:00:00Z]) == 0
      assert envelope.aggregate_type == nil
    end

    test "accepts a complete aggregate envelope" do
      attrs =
        valid_attrs(%{
          "aggregate_type" => "user",
          "aggregate_id" => "01912345-6789-7000-8000-000000000002",
          "aggregate_version" => 1,
          "trace_id" => "trace-1"
        })

      assert {:ok, envelope} = Envelope.validate(attrs)
      assert envelope.aggregate_version == 1
      assert envelope.trace_id == "trace-1"
    end

    test "rejects unknown fields" do
      assert {:error, {:invalid_envelope, errors}} =
               Envelope.validate(valid_attrs(%{"body" => "plaintext"}))

      assert "unknown field \"body\"" in errors
    end

    test "rejects missing required fields" do
      attrs = valid_attrs() |> Map.delete("occurred_at")
      assert {:error, {:invalid_envelope, errors}} = Envelope.validate(attrs)
      assert "missing required field \"occurred_at\"" in errors
    end

    test "rejects a partially filled aggregate" do
      attrs = valid_attrs(%{"aggregate_type" => "user"})
      assert {:error, {:invalid_envelope, errors}} = Envelope.validate(attrs)
      assert Enum.any?(errors, &(&1 =~ "all-or-none"))
    end

    test "rejects a bad event type" do
      assert {:error, {:invalid_envelope, _}} =
               Envelope.validate(valid_attrs(%{"type" => "User.Created"}))

      assert {:error, {:invalid_envelope, _}} =
               Envelope.validate(valid_attrs(%{"type" => "user"}))
    end

    test "rejects non-positive schema_version and aggregate_version" do
      assert {:error, _} = Envelope.validate(valid_attrs(%{"schema_version" => 0}))

      assert {:error, _} =
               Envelope.validate(
                 valid_attrs(%{
                   "aggregate_type" => "user",
                   "aggregate_id" => "01912345-6789-7000-8000-000000000002",
                   "aggregate_version" => 0
                 })
               )
    end

    test "rejects a non-object envelope" do
      assert {:error, {:invalid_envelope, _}} = Envelope.validate("nope")
    end

    test "rejects occurred_at values that are not ISO-8601 date-times" do
      for value <- ["garbage", 123, "2026-13-45T99:00:00Z"] do
        assert {:error, {:invalid_envelope, errors}} =
                 Envelope.validate(valid_attrs(%{"occurred_at" => value}))

        assert errors == ["field \"occurred_at\" must be an ISO-8601 date-time"]
      end
    end

    test "accepts an ISO-8601 offset for occurred_at" do
      assert {:ok, envelope} =
               Envelope.validate(valid_attrs(%{"occurred_at" => "2026-10-25T12:00:00+02:00"}))

      assert DateTime.diff(envelope.occurred_at, ~U[2026-10-25 10:00:00Z]) == 0
    end
  end

  describe "content_hash/1" do
    test "is stable regardless of key order" do
      {:ok, a} = Envelope.validate(valid_attrs())

      {:ok, b} =
        Envelope.validate(
          valid_attrs(%{
            "payload" => %{"user_id" => "01912345-6789-7000-8000-000000000002"},
            "type" => "user.created"
          })
        )

      assert Envelope.content_hash(a) == Envelope.content_hash(b)
    end

    test "changes when any effective field changes" do
      {:ok, a} = Envelope.validate(valid_attrs())
      {:ok, b} = Envelope.validate(valid_attrs(%{"trace_id" => "t2"}))
      {:ok, c} = Envelope.validate(valid_attrs(%{"payload" => %{"user_id" => "changed"}}))
      {:ok, d} = Envelope.validate(valid_attrs(%{"schema_version" => 2}))

      hash = Envelope.content_hash(a)
      refute hash == Envelope.content_hash(b)
      refute hash == Envelope.content_hash(c)
      refute hash == Envelope.content_hash(d)
    end

    test "is a lowercase 64-character hex digest" do
      {:ok, a} = Envelope.validate(valid_attrs())
      assert Envelope.content_hash(a) =~ ~r/^[0-9a-f]{64}$/
    end
  end
end

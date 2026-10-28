defmodule AsnEventBroker.Publishing do
  @moduledoc """
  Idempotent publish and fan-out (ADR 0008 §5, §7).

  One transaction inserts the event and one delivery per eligible
  subscription. `event_id` is the idempotency anchor and the stored
  `content_hash` (full canonical envelope) is the integrity anchor:

  - new `event_id`                    → `{:ok, :created}`
  - same id, same hash, same publisher → `{:ok, :duplicate}`
  - same id, different hash or publisher → `{:error, :conflict}`
  - a different `event_id` reusing an `aggregate_version` →
    `{:error, :aggregate_version_taken}` (422 at the edge)
  """

  alias AsnEventBroker.{Repo, Routing, Telemetry, UUIDv7}
  alias AsnEventBroker.Delivery.{Delivery, Waiters}
  alias AsnEventBroker.Events.{Event, Envelope}

  @spec publish(map(), String.t()) ::
          {:ok, :created}
          | {:ok, :duplicate}
          | {:error, :conflict}
          | {:error, :aggregate_version_taken}
          | {:error, {:invalid_envelope, [String.t()]}}
          | {:error, {:invalid_publisher, String.t()}}
  def publish(attrs, publisher)

  def publish(attrs, publisher) when is_binary(publisher) and publisher != "" do
    with {:ok, envelope} <- Envelope.validate(attrs) do
      hash = Envelope.content_hash(envelope)
      received_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      outcome =
        Repo.transaction(fn ->
          case insert_event(envelope, hash, publisher, received_at) do
            {:inserted, event} ->
              {:created, fan_out(event, received_at)}

            :conflict ->
              resolve_conflict(envelope, hash, publisher)
          end
        end)

      case outcome do
        {:ok, {:created, created}} ->
          # Wake parked claims only after the fan-out transaction committed,
          # and only when deliveries actually exist: an empty fan-out has
          # nothing to wake for.
          if created > 0, do: Waiters.wake_all()

          Telemetry.emit_count([:publish, :accepted], %{type: envelope.type, outcome: :created})
          {:ok, :created}

        {:ok, :duplicate} ->
          Telemetry.emit_count([:publish, :accepted], %{type: envelope.type, outcome: :duplicate})
          {:ok, :duplicate}

        {:ok, :conflict} ->
          Telemetry.emit_count([:publish, :rejected], %{reason: :conflict})
          {:error, :conflict}

        {:ok, :aggregate_version_taken} ->
          Telemetry.emit_count([:publish, :rejected], %{reason: :aggregate_version_taken})
          {:error, :aggregate_version_taken}
      end
    else
      {:error, {:invalid_envelope, _} = reason} ->
        Telemetry.emit_count([:publish, :rejected], %{reason: :invalid_envelope})
        {:error, reason}
    end
  end

  def publish(_attrs, _publisher), do: {:error, {:invalid_publisher, "publisher is required"}}

  # ON CONFLICT DO NOTHING without a conflict target swallows both the
  # event_id PK conflict and the aggregate-version partial unique conflict;
  # resolve_conflict tells them apart by re-reading the row.
  defp insert_event(envelope, _hash, publisher, received_at) do
    event = Event.new_from_envelope(envelope, publisher, received_at)

    row = %{
      event_id: event.event_id,
      type: event.type,
      schema_version: event.schema_version,
      occurred_at: event.occurred_at,
      aggregate_type: event.aggregate_type,
      aggregate_id: event.aggregate_id,
      aggregate_version: event.aggregate_version,
      trace_id: event.trace_id,
      payload: event.payload,
      content_hash: event.content_hash,
      publisher: event.publisher,
      received_at: event.received_at
    }

    case Repo.insert_all(Event, [row], on_conflict: :nothing) do
      {1, _} -> {:inserted, event}
      {0, _} -> :conflict
    end
  end

  defp resolve_conflict(envelope, hash, publisher) do
    case Repo.get(Event, envelope.event_id) do
      %Event{} = existing ->
        if existing.content_hash == hash and existing.publisher == publisher do
          :duplicate
        else
          :conflict
        end

      nil ->
        # Not an event_id conflict: the aggregate-version unique index rejected it.
        :aggregate_version_taken
    end
  end

  defp fan_out(event, now) do
    rows =
      event.type
      |> Routing.eligible_subscriptions()
      |> Enum.map(&delivery_row(event, &1, now))

    case rows do
      [] ->
        0

      rows ->
        {count, _} = Repo.insert_all(Delivery, rows)
        count
    end
  end

  defp delivery_row(event, subscription, now) do
    %{
      id: UUIDv7.generate(),
      subscription_id: subscription.id,
      event_id: event.event_id,
      aggregate_type: event.aggregate_type,
      aggregate_id: event.aggregate_id,
      aggregate_version: event.aggregate_version,
      state: :pending,
      attempts: 0,
      max_attempts: subscription.max_attempts,
      created_at: now,
      updated_at: now
    }
  end
end

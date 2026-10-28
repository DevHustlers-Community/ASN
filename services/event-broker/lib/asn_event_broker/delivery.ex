defmodule AsnEventBroker.Delivery do
  @moduledoc """
  Claim-side machinery: leases, per-aggregate ordering, in-flight caps, and
  long-poll waiting (ADR 0008 §1, §4, §6).

  A delivery is claimable only when it is the earliest non-terminal delivery
  for its `(subscription, aggregate_type, aggregate_id)` ordered by
  `aggregate_version` — head-of-line blocking is deliberate. Each claim takes
  a short `FOR UPDATE` lock on the subscription row to serialize concurrent
  claims; the lock is never held while parked. `attempts` increments at claim
  time so crashed consumers consume retry budget.
  """

  import Ecto.Query

  alias AsnEventBroker.Delivery.{Delivery, Waiters}
  alias AsnEventBroker.{Repo, Telemetry}
  alias AsnEventBroker.Subscriptions.Subscription

  @max_claim_batch 100

  # Earliest non-terminal per aggregate: a pending, leased, or dead earlier
  # version blocks later versions (head-of-line blocking is deliberate);
  # delivered and skipped do not block. Aggregate-less events are unordered.
  @claim_sql """
  UPDATE deliveries d
  SET state = 'leased',
      attempts = d.attempts + 1,
      lease_token_hash = $1,
      lease_expires_at = clock_timestamp() + ($2 * interval '1 second'),
      updated_at = $3
  WHERE d.id = (
    SELECT c.id
    FROM deliveries c
    WHERE c.subscription_id = $4
      AND c.state = 'pending'
      AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= clock_timestamp())
      AND (
        c.aggregate_type IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM deliveries e
          WHERE e.subscription_id = c.subscription_id
            AND e.aggregate_type = c.aggregate_type
            AND e.aggregate_id = c.aggregate_id
            AND e.state IN ('pending', 'leased', 'dead')
            AND e.id <> c.id
            AND e.aggregate_version < c.aggregate_version
        )
      )
    ORDER BY c.aggregate_version NULLS LAST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING d.id, d.event_id, d.aggregate_type, d.aggregate_id,
            d.aggregate_version, d.attempts, d.lease_expires_at
  """

  @spec claim(String.t(), pos_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, :not_found} | {:error, :paused}
  def claim(subscription_name, max, wait_ms)
      when is_binary(subscription_name) and max >= 1 do
    max = min(max, @max_claim_batch)

    case Repo.get_by(Subscription, name: subscription_name) do
      nil ->
        {:error, :not_found}

      %Subscription{status: :paused} ->
        {:error, :paused}

      %Subscription{} = subscription ->
        claim_loop(subscription.name, max, deadline(wait_ms))
    end
  end

  def claim(_name, _max, _wait_ms), do: {:error, :not_found}

  # One short transaction per attempt: resolve + lock the subscription row,
  # then lease up to `max` claimable deliveries. No connection is held while
  # parked.
  defp claim_once(name, max) do
    Repo.transaction(fn ->
      subscription = Repo.get_by!(Subscription, name: name)

      if subscription.status == :paused do
        Repo.rollback(:paused)
      end

      Repo.query!("SELECT id FROM subscriptions WHERE id = $1 FOR UPDATE", [
        uuid(subscription.id)
      ])

      allowed = delivery_cfg(:max_in_flight) - in_flight_count(subscription.id)
      lease_batch(subscription, max, min(max, allowed), [])
    end)
    |> case do
      {:ok, result} ->
        Telemetry.emit([:claim], %{count: length(result)}, %{subscription: name})
        {:ok, result}

      {:error, :paused} ->
        {:error, :paused}
    end
  end

  defp lease_batch(_subscription, _max, remaining, acc) when remaining <= 0,
    do: Enum.reverse(acc)

  defp lease_batch(subscription, max, remaining, acc) do
    now = utc_now()
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    case Repo.query!(@claim_sql, [
           hash(token),
           delivery_cfg(:lease_seconds),
           now,
           uuid(subscription.id)
         ]) do
      %{num_rows: 0} ->
        Enum.reverse(acc)

      %{columns: columns, rows: [row]} ->
        claimed = claimed_map(columns, row, token)
        lease_batch(subscription, max, remaining - 1, [claimed | acc])
    end
  end

  defp in_flight_count(subscription_id) do
    Repo.one!(
      from d in Delivery,
        where: d.subscription_id == ^subscription_id and d.state == :leased,
        select: count()
    )
  end

  defp claim_loop(name, max, deadline) do
    case claim_once(name, max) do
      {:ok, [_ | _] = claimed} ->
        {:ok, claimed}

      {:error, :paused} ->
        {:error, :paused}

      {:ok, []} ->
        if remaining_ms(deadline) <= 0 do
          {:ok, []}
        else
          Waiters.join()

          # Re-check after joining to close the wake race between the first
          # check and the join.
          case claim_once(name, max) do
            {:ok, [_ | _] = claimed} ->
              Waiters.leave()
              {:ok, claimed}

            _parked ->
              receive do
                :wake -> :woken
              after
                min(remaining_ms(deadline), delivery_cfg(:sweep_interval_ms)) -> :sweep
              end

              Waiters.leave()
              claim_loop(name, max, deadline)
          end
        end
    end
  end

  defp deadline(wait_ms), do: System.monotonic_time(:millisecond) + wait_ms

  defp remaining_ms(deadline),
    do: max(0, deadline - System.monotonic_time(:millisecond))

  defp claimed_map(columns, row, token) do
    values =
      columns
      |> Enum.zip(row)
      |> Map.new(fn {column, value} ->
        {String.to_existing_atom(column), normalize_column(column, value)}
      end)

    %{
      delivery_id: Map.fetch!(values, :id),
      event_id: Map.fetch!(values, :event_id),
      aggregate_type: Map.fetch!(values, :aggregate_type),
      aggregate_id: Map.fetch!(values, :aggregate_id),
      aggregate_version: Map.fetch!(values, :aggregate_version),
      attempts: Map.fetch!(values, :attempts),
      lease_token: token,
      lease_expires_at: Map.fetch!(values, :lease_expires_at)
    }
  end

  defp normalize_column(column, value)
       when column in ["id", "event_id", "aggregate_id"] and value != nil,
       do: Ecto.UUID.load!(value)

  # Raw queries return timestamptz as NaiveDateTime; normalize to UTC DateTime.
  defp normalize_column(_column, %NaiveDateTime{} = value),
    do: DateTime.from_naive!(value, "Etc/UTC")

  defp normalize_column(_column, value), do: value

  defp delivery_cfg(key),
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :delivery), key)

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp uuid(value), do: Ecto.UUID.dump!(value)
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end

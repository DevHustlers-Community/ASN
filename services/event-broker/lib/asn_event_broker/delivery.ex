defmodule AsnEventBroker.Delivery do
  @moduledoc """
  Claim-side machinery: leases, per-aggregate ordering, in-flight caps, and
  long-poll waiting (ADR 0008 §1, §4, §6).

  A delivery is claimable only when it is the earliest non-terminal delivery
  for its `(subscription, aggregate_type, aggregate_id)` ordered by
  `aggregate_version` — head-of-line blocking is deliberate. An idle sweep
  runs one cheap check and takes no lock; the `FOR UPDATE` lock on the
  subscription row is only taken when that check says a claim is possible.
  The lock is never held while parked. `attempts` increments at claim
  time so crashed consumers consume retry budget.

  One statement leases the whole batch: candidates are selected up to the
  in-flight cap and updated in place, with one lease token per delivery.
  Selection is not globally ordered (ADR 0008 §6); ordering is guaranteed per
  aggregate only.
  """

  import Ecto.Query

  alias AsnEventBroker.Delivery.{Delivery, Waiters}
  alias AsnEventBroker.{Repo, Telemetry}

  @max_claim_batch 100

  # One statement leases the whole batch. Candidate selection has no global
  # ORDER BY: ADR 0008 §6 guarantees ordering per aggregate only, and the
  # anti-join below enforces it (a pending, leased, or dead earlier version
  # blocks later versions; delivered and skipped do not). Sorting the
  # subscription's whole pending backlog per claim is what made the old
  # one-row loop O(backlog) per claimed row.
  #
  # Candidates are numbered only to give each delivery its own token from the
  # caller's array. The window runs over the LIMITed set, not the backlog.
  # `FOR UPDATE SKIP LOCKED` is unnecessary: the SELECT does not lock, and the
  # subscription-row lock serializes claimers of one subscription.
  @claim_sql """
  WITH candidates AS (
    SELECT c.id
    FROM deliveries c
    WHERE c.subscription_id = $3
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
    LIMIT $4
  ),
  numbered AS (
    SELECT id, row_number() OVER (ORDER BY id) AS rn
    FROM candidates
  ),
  claimed AS (
    UPDATE deliveries d
    SET state = 'leased',
        attempts = d.attempts + 1,
        lease_token_hash = ($1::text[])[n.rn],
        lease_expires_at = clock_timestamp() + ($2 * interval '1 second'),
        updated_at = $5
    FROM numbered n
    WHERE d.id = n.id
    RETURNING n.rn, d.id, d.event_id, d.aggregate_type, d.aggregate_id,
              d.aggregate_version, d.attempts, d.lease_expires_at
  )
  SELECT rn, id, event_id, aggregate_type, aggregate_id, aggregate_version,
         attempts, lease_expires_at
  FROM claimed
  ORDER BY rn
  """

  # Cheap idle check: one row with the facts the loop needs before it takes
  # any lock. The anti-join mirrors @claim_sql, so a head-of-line blocked row
  # does not look claimable.
  @check_sql """
  SELECT s.id, s.status,
         (SELECT count(*)
          FROM deliveries l
          WHERE l.subscription_id = s.id
            AND l.state = 'leased') AS leased,
         EXISTS (
           SELECT 1
           FROM deliveries c
           WHERE c.subscription_id = s.id
             AND c.state = 'pending'
             AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= statement_timestamp())
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
         ) AS claimable
  FROM subscriptions s
  WHERE s.name = $1
  """

  @spec claim(String.t(), pos_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, :not_found} | {:error, :paused}
  def claim(subscription_name, max, wait_ms)
      when is_binary(subscription_name) and max >= 1 do
    max = min(max, @max_claim_batch)
    claim_loop(subscription_name, max, deadline(wait_ms))
  end

  def claim(_name, _max, _wait_ms), do: {:error, :not_found}

  # One wakeup-safe iteration. The process joins the registry *before* the
  # check, so a publish that commits after the check leaves a `:wake` in the
  # mailbox; wakes received before the check are flushed because the check
  # already observed them. An idle sweep therefore runs one statement and
  # takes no lock.
  defp claim_loop(name, max, deadline) do
    Waiters.join(name)
    flush_wakes()

    outcome =
      case check(name) do
        nil ->
          {:error, :not_found}

        %{status: :paused} ->
          {:error, :paused}

        check ->
          if claimable?(check) do
            claim_once(name, check.id, max)
          else
            Telemetry.emit([:claim], %{count: 0}, %{subscription: name})
            {:ok, []}
          end
      end

    case outcome do
      {:ok, []} ->
        if remaining_ms(deadline) <= 0 do
          Waiters.leave(name)
          {:ok, []}
        else
          receive do
            :wake -> :ok
          after
            min(remaining_ms(deadline), delivery_cfg(:sweep_interval_ms)) -> :ok
          end

          Waiters.leave(name)
          claim_loop(name, max, deadline)
        end

      result ->
        Waiters.leave(name)
        result
    end
  end

  # `statement_timestamp()` is stable for the statement (so PostgreSQL can use
  # it as an index bound) but, unlike `now()`, is not pinned to the start of an
  # enclosing transaction, which the test sandbox holds open for a whole test.
  # The check only decides whether an attempt is worth a transaction; the
  # claim re-checks under the row lock with `clock_timestamp()`.
  defp check(name) do
    case Repo.query!(@check_sql, [name]) do
      %{rows: [[id, status, leased, claimable]]} ->
        %{
          id: Ecto.UUID.load!(id),
          status: subscription_status(status),
          leased: leased,
          claimable: claimable
        }

      %{rows: []} ->
        nil
    end
  end

  defp subscription_status("active"), do: :active
  defp subscription_status("paused"), do: :paused

  defp claimable?(%{claimable: true, leased: leased}),
    do: leased < delivery_cfg(:max_in_flight)

  defp claimable?(_check), do: false

  # One short transaction per attempt: lock the subscription row, then lease
  # up to `max` claimable deliveries. No connection is held while parked.
  defp claim_once(name, subscription_id, max) do
    Repo.transaction(fn ->
      case Repo.query!("SELECT status FROM subscriptions WHERE id = $1 FOR UPDATE", [
             uuid(subscription_id)
           ]) do
        %{rows: [[status]]} ->
          if status == "paused", do: Repo.rollback(:paused)

          allowed = delivery_cfg(:max_in_flight) - in_flight_count(subscription_id)
          lease_batch(subscription_id, min(max, allowed))

        %{rows: []} ->
          Repo.rollback(:not_found)
      end
    end)
    |> case do
      {:ok, result} ->
        Telemetry.emit([:claim], %{count: length(result)}, %{subscription: name})
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp flush_wakes do
    receive do
      :wake -> flush_wakes()
    after
      0 -> :ok
    end
  end

  defp lease_batch(_subscription_id, remaining) when remaining <= 0, do: []

  defp lease_batch(subscription_id, remaining) do
    tokens = Enum.map(1..remaining, fn _ -> new_token() end)

    %{columns: columns, rows: rows} =
      Repo.query!(@claim_sql, [
        Enum.map(tokens, &hash/1),
        delivery_cfg(:lease_seconds),
        uuid(subscription_id),
        remaining,
        utc_now()
      ])

    Enum.map(rows, &claimed_map(columns, &1, tokens))
  end

  defp new_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp in_flight_count(subscription_id) do
    Repo.one!(
      from d in Delivery,
        where: d.subscription_id == ^subscription_id and d.state == :leased,
        select: count()
    )
  end

  defp deadline(wait_ms), do: System.monotonic_time(:millisecond) + wait_ms

  defp remaining_ms(deadline),
    do: max(0, deadline - System.monotonic_time(:millisecond))

  defp claimed_map(columns, row, tokens) do
    values =
      columns
      |> Enum.zip(row)
      |> Map.new(fn
        {"rn", rn} -> {:rn, rn}
        {column, value} -> {String.to_existing_atom(column), normalize_column(column, value)}
      end)

    %{
      delivery_id: Map.fetch!(values, :id),
      event_id: Map.fetch!(values, :event_id),
      aggregate_type: Map.fetch!(values, :aggregate_type),
      aggregate_id: Map.fetch!(values, :aggregate_id),
      aggregate_version: Map.fetch!(values, :aggregate_version),
      attempts: Map.fetch!(values, :attempts),
      lease_token: Enum.at(tokens, Map.fetch!(values, :rn) - 1),
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

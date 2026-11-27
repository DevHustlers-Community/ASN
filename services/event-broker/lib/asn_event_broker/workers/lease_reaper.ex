defmodule AsnEventBroker.Workers.LeaseReaper do
  @moduledoc """
  Returns expired leases to `pending`, or dead-letters them when attempts are
  exhausted (ADR 0008 §3, §5). Redelivery after expiry is the at-least-once
  path; consumers deduplicate on `event_id`.

  The logic lives in `reap/0` so tests call it directly; the GenServer is
  only the scheduler and is disabled under the test sandbox.
  """

  use GenServer

  alias AsnEventBroker.{Repo, Retries, Telemetry}

  @reap_sql """
  UPDATE deliveries
  SET state = CASE WHEN attempts >= max_attempts THEN 'dead' ELSE 'pending' END,
      dead_lettered_at = CASE WHEN attempts >= max_attempts THEN clock_timestamp() ELSE NULL END,
      next_attempt_at = CASE
        WHEN attempts >= max_attempts THEN NULL
        ELSE clock_timestamp() + (
          floor(random() * LEAST(
            $1::double precision,
            $2::double precision * power(2::double precision, attempts - 1)
          )) + 1
        ) * interval '1 millisecond'
      END,
      lease_token_hash = NULL,
      lease_expires_at = NULL,
      updated_at = clock_timestamp()
  WHERE state = 'leased' AND lease_expires_at <= clock_timestamp()
  RETURNING id
  """

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule_reap()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:reap, state) do
    reap()
    schedule_reap()
    {:noreply, state}
  end

  @doc "Reaps every expired lease once and returns the number of rows affected."
  @spec reap() :: non_neg_integer()
  def reap do
    # Keep the reaper as one batched statement. The SQL mirrors
    # Retries.next_delay_ms/1: full jitter from 1 through the capped exponential
    # delay, calculated on the database clock.
    case Repo.query!(@reap_sql, [
           Retries.delivery_cfg(:backoff_cap_ms),
           Retries.delivery_cfg(:backoff_base_ms)
         ]) do
      %{num_rows: count} ->
        if count > 0, do: Telemetry.emit([:lease_expired], %{count: count}, %{})
        count
    end
  end

  defp schedule_reap do
    Process.send_after(self(), :reap, reaper_interval_ms())
  end

  defp reaper_interval_ms,
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :delivery), :reaper_interval_ms)
end

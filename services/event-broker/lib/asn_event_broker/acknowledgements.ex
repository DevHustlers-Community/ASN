defmodule AsnEventBroker.Acknowledgements do
  @moduledoc """
  Ack/nack/extend with exact lease-token semantics (ADR 0008 §3, §4).

  Only the current lease's token can act, and only while the lease is
  unexpired by database time. A delivered row keeps its final lease token
  hash, so repeating the ack with that same token is an idempotent 200; any
  superseded token returns `{:error, :stale_lease}` (409 at the edge) and can
  never change state.
  """

  alias AsnEventBroker.{Repo, Retries, Telemetry}
  alias AsnEventBroker.Delivery.Delivery

  @ack_sql """
  UPDATE deliveries
  SET state = 'delivered',
      delivered_at = $2,
      lease_expires_at = NULL,
      updated_at = $2
  WHERE id = $1
    AND (
      (state = 'leased' AND lease_token_hash = $3 AND lease_expires_at > clock_timestamp())
      OR (state = 'delivered' AND lease_token_hash = $3)
    )
  RETURNING id
  """

  @nack_sql """
  UPDATE deliveries
  SET state = CASE WHEN attempts >= max_attempts THEN 'dead' ELSE 'pending' END,
      dead_lettered_at = CASE WHEN attempts >= max_attempts THEN $2::timestamptz ELSE NULL END,
      lease_token_hash = NULL,
      lease_expires_at = NULL,
      last_error_kind = $3,
      last_error_message = $4,
      updated_at = $2
  WHERE id = $1
    AND state = 'leased'
    AND lease_token_hash = $5
    AND lease_expires_at > clock_timestamp()
  RETURNING state, attempts
  """

  @schedule_sql """
  UPDATE deliveries
  SET next_attempt_at = clock_timestamp() + ($2 * interval '1 millisecond')
  WHERE id = $1 AND state = 'pending'
  """

  @extend_sql """
  UPDATE deliveries
  SET lease_expires_at = clock_timestamp() + ($3 * interval '1 second'), updated_at = $2
  WHERE id = $1
    AND state = 'leased'
    AND lease_token_hash = $4
    AND lease_expires_at > clock_timestamp()
  RETURNING lease_expires_at
  """

  @spec ack(String.t(), String.t()) ::
          :ok | {:error, :not_found} | {:error, :stale_lease} | {:error, :invalid_request}
  def ack(delivery_id, lease_token) when is_binary(lease_token) and lease_token != "" do
    now = utc_now()

    case Repo.query!(@ack_sql, [uuid(delivery_id), now, hash(lease_token)]) do
      %{num_rows: 1} ->
        Telemetry.emit_count([:ack], %{})
        :ok

      _ ->
        classify_failure(delivery_id)
    end
  end

  def ack(_delivery_id, _lease_token), do: {:error, :invalid_request}

  @spec nack(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, :pending}
          | {:ok, :dead}
          | {:error, :not_found}
          | {:error, :stale_lease}
          | {:error, :invalid_request}
  def nack(delivery_id, lease_token, error_kind, error_message \\ nil)

  def nack(delivery_id, lease_token, error_kind, error_message)
      when is_binary(lease_token) and lease_token != "" do
    now = utc_now()

    outcome =
      Repo.transaction(fn ->
        case Repo.query!(@nack_sql, [
               uuid(delivery_id),
               now,
               truncate(error_kind),
               truncate(error_message),
               hash(lease_token)
             ]) do
          %{num_rows: 1, rows: [["dead", _attempts]]} ->
            :dead

          %{num_rows: 1, rows: [["pending", attempts]]} ->
            # Backoff is computed from the actual attempts (incremented at
            # claim time). The delay is measured on the database clock so the
            # schedule agrees with the database-time guards. The state change
            # and its reschedule commit in the same transaction, so a crash can
            # no longer leave a pending row with a stale next_attempt_at.
            delay_ms = Retries.next_delay_ms(attempts)
            Repo.query!(@schedule_sql, [uuid(delivery_id), delay_ms])
            :pending

          %{num_rows: 0} ->
            :no_match
        end
      end)

    case outcome do
      {:ok, :dead} ->
        Telemetry.emit_count([:nack], %{})
        Telemetry.emit_count([:dead_letter], %{})
        {:ok, :dead}

      {:ok, :pending} ->
        Telemetry.emit_count([:nack], %{})
        {:ok, :pending}

      {:ok, :no_match} ->
        classify_failure(delivery_id)
    end
  end

  def nack(_delivery_id, _lease_token, _error_kind, _error_message),
    do: {:error, :invalid_request}

  @spec extend(String.t(), String.t()) ::
          {:ok, DateTime.t()}
          | {:error, :not_found}
          | {:error, :stale_lease}
          | {:error, :invalid_request}
  def extend(delivery_id, lease_token) when is_binary(lease_token) and lease_token != "" do
    now = utc_now()
    lease_seconds = delivery_cfg(:lease_seconds)

    case Repo.query!(@extend_sql, [uuid(delivery_id), now, lease_seconds, hash(lease_token)]) do
      %{num_rows: 1, rows: [[expires_at]]} -> {:ok, normalize_timestamp(expires_at)}
      _ -> classify_failure(delivery_id)
    end
  end

  def extend(_delivery_id, _lease_token), do: {:error, :invalid_request}

  defp classify_failure(delivery_id) do
    case Repo.get(Delivery, delivery_id) do
      nil -> {:error, :not_found}
      %Delivery{} -> {:error, :stale_lease}
    end
  end

  defp truncate(nil), do: nil
  defp truncate(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp truncate(value), do: value |> to_string() |> String.slice(0, 500)

  defp delivery_cfg(key),
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :delivery), key)

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp uuid(value), do: Ecto.UUID.dump!(value)
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  # Raw queries return timestamptz as NaiveDateTime; normalize to UTC DateTime.
  defp normalize_timestamp(%NaiveDateTime{} = value),
    do: DateTime.from_naive!(value, "Etc/UTC")

  defp normalize_timestamp(%DateTime{} = value), do: value
end

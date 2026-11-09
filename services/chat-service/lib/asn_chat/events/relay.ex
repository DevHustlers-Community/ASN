defmodule AsnChat.Events.Relay do
  @moduledoc """
  Publishes committed outbox rows to the broker (ADR 0008 §5, producer relay
  contract):

  - Per aggregate, version N is published and N+1 is not attempted until N is
    definitively accepted (201 or 200).
  - Timeouts, transport errors, 408, 425, 429, and 5xx responses are retried:
    the relay stops the failed aggregate and the next tick retries the SAME
    event id with identical rebuilt content — idempotent publish makes that
    safe. Other aggregates are not blocked.
  - A 400, 401, 403, 404, 409, 413, 422, or any other unexpected status is a
    producer or configuration bug: the relay halts the remaining events of that
    aggregate and alerts (logged) rather than skipping ahead. Other aggregates
    continue.

  The HTTP client is injectable for tests; the default posts to
  `POST {BROKER_BASE_URL}/v1/events` with `BROKER_SERVICE_ID` /
  `BROKER_SERVICE_TOKEN` bearer credentials and `BROKER_PUBLISH_TIMEOUT_MS`.
  """

  use GenServer
  require Logger

  alias AsnChat.Events.{Envelope, Outbox}

  @relay_registry __MODULE__

  # Responses that mean "try the identical event again later".
  @retryable_statuses [408, 425, 429]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @relay_registry)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    publish_batch()
    schedule_tick()
    {:noreply, state}
  end

  @doc """
  Processes the unpublished outbox once and returns `{:ok, published}` with the
  ids of the events accepted by the broker.

  Rows for one aggregate are attempted in version order and stop at the first
  non-acceptance; other aggregates still progress.
  """
  @spec publish_batch(keyword()) :: {:ok, [String.t()]}
  def publish_batch(opts \\ []) do
    client = Keyword.get(opts, :http_client, &http_publish/1)

    published =
      Outbox.unpublished()
      |> Enum.chunk_by(&aggregate_key/1)
      |> Enum.flat_map(&publish_aggregate(&1, client))

    {:ok, published}
  end

  # Events without an aggregate have no ordering constraint, so each is its own
  # group and a failure cannot block the others.
  defp aggregate_key(%{aggregate_type: nil, id: id}), do: {:single, id}
  defp aggregate_key(row), do: {:aggregate, row.aggregate_type, row.aggregate_id}

  defp publish_aggregate(rows, client) do
    rows
    |> Enum.reduce_while([], fn row, acc ->
      case publish_one(row, client) do
        {:ok, :accepted} ->
          Outbox.mark_published(row.id)
          {:cont, [row.id | acc]}

        {:error, {:retryable, reason}} ->
          # Timeout/transport ambiguity or a transient broker state: stop this
          # aggregate and retry the same event id on the next tick.
          Logger.warning(
            "broker publish for #{row.id} not confirmed (#{describe(reason)}); will retry"
          )

          {:halt, acc}

        {:error, {:rejected, reason}} ->
          # Producer or configuration bug: retrying cannot fix it.
          Logger.critical(
            "broker rejected outbox event #{row.id} (#{describe(reason)}): " <>
              "producer bug, halting this aggregate"
          )

          {:halt, acc}
      end
    end)
    |> Enum.reverse()
  end

  defp publish_one(row, client) do
    envelope = Envelope.from_outbox(row)

    case client.(envelope) do
      {:ok, status} when status in [200, 201] ->
        {:ok, :accepted}

      {:ok, status} when status in @retryable_statuses or status in 500..599 ->
        {:error, {:retryable, {:http_status, status}}}

      {:ok, status} ->
        {:error, {:rejected, {:http_status, status}}}

      {:error, reason} ->
        {:error, {:retryable, reason}}
    end
  end

  defp describe({:http_status, status}), do: "HTTP #{status}"
  defp describe(reason), do: inspect(reason)

  defp http_publish(envelope) do
    url = String.trim_trailing(base_url(), "/") <> "/v1/events"
    body = Jason.encode!(envelope)

    headers = [
      {~c"authorization", ~c"Bearer " ++ String.to_charlist(service_token())},
      {~c"content-type", ~c"application/json"}
    ]

    request = {
      String.to_charlist(url),
      headers,
      ~c"application/json",
      body
    }

    http_options = [timeout: timeout_ms(), connect_timeout: timeout_ms()]

    case :httpc.request(:post, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _phrase}, _headers, _body}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, relay_cfg(:interval_ms))
  end

  defp base_url, do: System.get_env("BROKER_BASE_URL", "http://localhost:4004")
  defp service_token, do: System.get_env("BROKER_SERVICE_TOKEN", "change_me")

  defp timeout_ms,
    do: relay_cfg(:publish_timeout_ms)

  defp relay_cfg(key), do: Keyword.fetch!(Application.fetch_env!(:asn_chat, :events_relay), key)
end

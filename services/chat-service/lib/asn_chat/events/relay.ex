defmodule AsnChat.Events.Relay do
  @moduledoc """
  Publishes committed outbox rows to the broker (ADR 0008 §5, producer relay
  contract):

  - Per aggregate, version N is published and N+1 is not attempted until N is
    definitively accepted (201 or 200).
  - Timeouts and ambiguous outcomes retry the SAME event_id with identical
    content — idempotent publish makes that safe.
  - A 409 or 422 is a producer bug: the relay halts that batch and alerts
    (logged) rather than skipping ahead.

  The HTTP client is injectable for tests; the default posts to
  `POST {BROKER_BASE_URL}/v1/events` with `BROKER_SERVICE_ID` /
  `BROKER_SERVICE_TOKEN` bearer credentials and `BROKER_PUBLISH_TIMEOUT_MS`.
  """

  use GenServer
  require Logger

  alias AsnChat.Events.Outbox

  @relay_registry __MODULE__

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
  Processes the unpublished outbox once and returns
  `{:ok, published}` with the event_ids accepted by the broker.
  """
  @spec publish_batch(keyword()) :: {:ok, [String.t()]}
  def publish_batch(opts \\ []) do
    client = Keyword.get(opts, :http_client, &http_publish/1)
    rows = Outbox.unpublished()

    {published, _halted?} =
      Enum.reduce_while(rows, {[], false}, fn row, {acc, _} ->
        case publish_one(row, client) do
          {:ok, :accepted} ->
            Outbox.mark_published(row.event_id)
            {:cont, {[row.event_id | acc], false}}

          {:error, :halt} ->
            # Producer-contract violation (409/422): stop the batch, alert.
            Logger.critical(
              "broker rejected outbox event #{row.event_id} (409/422): producer bug, halting relay"
            )

            {:halt, {acc, true}}

          {:error, reason} ->
            # Timeout/transport ambiguity: stop and retry the same event_id on
            # the next tick (idempotent publish makes this safe).
            Logger.warning(
              "broker publish for #{row.event_id} not confirmed (#{inspect(reason)}); will retry"
            )

            {:halt, {acc, true}}
        end
      end)

    {:ok, Enum.reverse(published)}
  end

  defp publish_one(row, client) do
    case client.(row.envelope) do
      {:ok, status} when status in [200, 201] -> {:ok, :accepted}
      {:ok, status} when status in [409, 422] -> {:error, :halt}
      {:error, reason} -> {:error, reason}
    end
  end

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

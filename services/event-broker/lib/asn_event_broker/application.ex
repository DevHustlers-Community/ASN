defmodule AsnEventBroker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AsnEventBroker.Repo,
        AsnEventBroker.Delivery.Waiters,
        AsnEventBroker.Web.Metrics
      ]
      |> maybe_add_workers()

    with_http(children)
    |> Supervisor.start_link(strategy: :one_for_one, name: AsnEventBroker.Supervisor)
    |> tap(fn
      {:ok, _pid} ->
        if Application.get_env(:asn_event_broker, :bootstrap_admin, true) do
          AsnEventBroker.Security.bootstrap_admin()
        end

      _ ->
        :ok
    end)
  end

  # Scheduled workers and the HTTP listener run against the real world; they
  # are disabled under the test sandbox, which exercises their logic by
  # calling it directly (HTTP tests go through Plug.Test).
  defp maybe_add_workers(children) do
    if Application.get_env(:asn_event_broker, :start_workers, true) do
      children ++ [AsnEventBroker.Workers.LeaseReaper]
    else
      children
    end
  end

  defp with_http(children) do
    http = Application.get_env(:asn_event_broker, :http, [])

    if Keyword.get(http, :enabled, true) do
      children ++ [{Bandit, plug: AsnEventBroker.Web.Router, port: Keyword.fetch!(http, :port)}]
    else
      children
    end
  end
end

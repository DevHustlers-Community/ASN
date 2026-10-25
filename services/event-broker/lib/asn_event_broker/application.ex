defmodule AsnEventBroker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AsnEventBroker.Repo,
        AsnEventBroker.Delivery.Waiters
      ]
      |> maybe_add_workers()

    opts = [strategy: :one_for_one, name: AsnEventBroker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Scheduled workers run against the real database; they are disabled under
  # the test sandbox, which exercises their logic by calling it directly.
  defp maybe_add_workers(children) do
    if Application.get_env(:asn_event_broker, :start_workers, true) do
      children ++ [AsnEventBroker.Workers.LeaseReaper]
    else
      children
    end
  end
end

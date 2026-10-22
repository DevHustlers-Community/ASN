defmodule AsnEventBroker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AsnEventBroker.Repo
    ]

    opts = [strategy: :one_for_one, name: AsnEventBroker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule AsnEventBroker.DataCase do
  @moduledoc """
  Test case for database-backed broker tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias AsnEventBroker.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AsnEventBroker.DataCase
    end
  end

  setup tags do
    AsnEventBroker.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AsnEventBroker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end

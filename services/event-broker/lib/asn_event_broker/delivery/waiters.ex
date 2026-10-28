defmodule AsnEventBroker.Delivery.Waiters do
  @moduledoc """
  In-process wakeup registry for parked claims (ADR 0008 §1).

  Long-poll claims park on this registry instead of busy-polling the
  database. Publishing wakes all parked claims; a configurable fallback sweep
  bounds the cost of a missed wakeup, so correctness never depends on
  wakeups. `:pg` scopes keep this single-node-simple; `LISTEN/NOTIFY` can
  replace it if the broker ever spans nodes.
  """

  use GenServer

  @scope :asn_event_broker
  @group :delivery_claims

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case :pg.start_link(@scope) do
      {:ok, _pid} -> {:ok, %{}}
      {:error, {:already_started, _pid}} -> {:ok, %{}}
    end
  end

  @doc "Registers the calling process for wakeup on the next publish."
  @spec join() :: true
  def join, do: :pg.join(@scope, @group, self())

  @spec leave() :: true
  def leave, do: :pg.leave(@scope, @group, self())

  @doc "Wakes every parked claim on this node."
  @spec wake_all() :: :ok
  def wake_all do
    for pid <- :pg.get_local_members(@scope, @group) do
      send(pid, :wake)
    end

    :ok
  end
end

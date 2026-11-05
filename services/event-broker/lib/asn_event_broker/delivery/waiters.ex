defmodule AsnEventBroker.Delivery.Waiters do
  @moduledoc """
  In-process wakeup registry for parked claims (ADR 0008 §1).

  Long-poll claims park on this registry instead of busy-polling the
  database. Publishing wakes only the claims parked for the subscriptions
  that received deliveries; a configurable fallback sweep bounds the cost of
  a missed wakeup, so correctness never depends on wakeups. `:pg` scopes keep
  this single-node-simple; `LISTEN/NOTIFY` can replace it if the broker ever
  spans nodes.
  """

  use GenServer

  @scope :asn_event_broker

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case :pg.start_link(@scope) do
      {:ok, _pid} -> {:ok, %{}}
      {:error, {:already_started, _pid}} -> {:ok, %{}}
    end
  end

  @doc """
  Registers the calling process for wakeup on the next publish that fans out
  to `subscription_name`.
  """
  @spec join(String.t()) :: true
  def join(subscription_name), do: :pg.join(@scope, group(subscription_name), self())

  @spec leave(String.t()) :: true
  def leave(subscription_name), do: :pg.leave(@scope, group(subscription_name), self())

  @doc """
  Wakes the parked claims for `subscription_names` on this node.

  A process can only be parked for one subscription at a time, but the
  registry is deduplicated anyway so a future caller cannot deliver the same
  `:wake` twice.
  """
  @spec wake([String.t()]) :: :ok
  def wake(subscription_names) do
    subscription_names
    |> Enum.uniq()
    |> Enum.flat_map(&:pg.get_local_members(@scope, group(&1)))
    |> Enum.uniq()
    |> Enum.each(&send(&1, :wake))

    :ok
  end

  defp group(subscription_name), do: {:subscription, subscription_name}
end

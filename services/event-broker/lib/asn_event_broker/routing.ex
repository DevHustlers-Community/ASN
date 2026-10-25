defmodule AsnEventBroker.Routing do
  @moduledoc """
  Fan-out selection: which active subscriptions are eligible for an event.

  Eligibility is `status == active` and either no `event_types` filter (all
  types) or the event type listed in the filter. Paused subscriptions stay
  eligible for fan-out — their deliveries are created but not claimable
  (ADR 0008 §7).
  """

  import Ecto.Query

  alias AsnEventBroker.Repo
  alias AsnEventBroker.Subscriptions.Subscription

  def eligible_subscriptions(event_type) do
    Repo.all(
      from s in Subscription,
        where: s.status == :active or s.status == :paused,
        where: is_nil(s.event_types) or ^event_type in s.event_types
    )
  end
end

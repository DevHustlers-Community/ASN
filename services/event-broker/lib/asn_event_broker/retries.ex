defmodule AsnEventBroker.Retries do
  @moduledoc """
  Bounded exponential backoff with full jitter (ADR 0008 §5): the next delay
  is drawn uniformly from 1 up to `min(cap, base * 2^(attempts - 1))`.
  """

  def next_delay_ms(attempts) when attempts >= 1 do
    base = delivery_cfg(:backoff_base_ms)
    cap = delivery_cfg(:backoff_cap_ms)
    exponential = min(cap, base * 2 ** (attempts - 1))
    :rand.uniform(exponential)
  end

  def delivery_cfg(key),
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :delivery), key)
end

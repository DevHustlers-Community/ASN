defmodule AsnEventBrokerTest do
  use ExUnit.Case, async: true

  test "the broker application is defined" do
    assert Application.spec(:asn_event_broker, :vsn)
  end
end

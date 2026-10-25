defmodule AsnEventBroker.UUIDv7 do
  @moduledoc """
  Minimal RFC 9562 UUIDv7 generation for broker-owned identifiers.

  Placeholder pending the UUIDv7 library decision for the Elixir runtime
  (architecture document §9, item 16): the format is fixed by the data
  conventions, and any vetted library chosen later replaces this module
  behind the same `generate/0` interface.
  """

  @spec generate() :: String.t()
  def generate do
    unix_ms = System.system_time(:millisecond)

    <<rand_a::integer-size(12), rand_b::integer-size(62), _::integer-size(6)>> =
      :crypto.strong_rand_bytes(10)

    <<unix_ms::integer-size(48), 7::integer-size(4), rand_a::integer-size(12), 2::integer-size(2),
      rand_b::integer-size(62)>>
    |> format()
  end

  defp format(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
           e::binary-size(6)>>
       ) do
    Base.encode16(a <> b <> c <> d <> e, case: :lower)
    |> then(fn hex ->
      [
        String.slice(hex, 0, 8),
        String.slice(hex, 8, 4),
        String.slice(hex, 12, 4),
        String.slice(hex, 16, 4),
        String.slice(hex, 20, 12)
      ]
    end)
    |> Enum.join("-")
  end
end

defmodule AsnChat.UUIDv7 do
  @moduledoc """
  Minimal RFC 9562 UUIDv7 generation for chat-owned identifiers.

  Placeholder pending the UUIDv7 library decision for the Elixir runtime
  (architecture document §9, item 16); kept independent from the broker's
  module because services share no runtime code (ADR 0011).
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
    hex = Base.encode16(a <> b <> c <> d <> e, case: :lower)

    [
      String.slice(hex, 0, 8),
      String.slice(hex, 8, 4),
      String.slice(hex, 12, 4),
      String.slice(hex, 16, 4),
      String.slice(hex, 20, 12)
    ]
    |> Enum.join("-")
  end
end

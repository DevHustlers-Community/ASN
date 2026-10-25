defmodule AsnEventBroker.UUIDv7Test do
  use ExUnit.Case, async: true

  alias AsnEventBroker.UUIDv7

  @v7_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

  test "generates RFC 9562 v7 format" do
    for _ <- 1..200 do
      assert UUIDv7.generate() =~ @v7_regex
    end
  end

  test "encodes the current unix time in milliseconds" do
    uuid = UUIDv7.generate()

    <<ms::integer-size(48)>> =
      uuid
      |> String.replace("-", "")
      |> Base.decode16!(case: :lower)
      |> binary_part(0, 6)

    assert abs(ms - System.system_time(:millisecond)) < 5_000
  end

  test "timestamp portion is monotonically non-decreasing" do
    ids = for _ <- 1..50, do: UUIDv7.generate()

    timestamps =
      Enum.map(ids, fn id ->
        <<ms::integer-size(48)>> =
          id |> String.replace("-", "") |> Base.decode16!(case: :lower) |> binary_part(0, 6)

        ms
      end)

    assert timestamps == Enum.sort(timestamps)
  end

  test "is unique across a burst" do
    ids = for _ <- 1..1_000, do: UUIDv7.generate()
    assert Enum.uniq(ids) == ids
  end
end

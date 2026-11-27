defmodule AsnSocial.UUIDv7Test do
  use ExUnit.Case, async: true

  test "generates RFC 9562 UUIDv7 values" do
    ids = Enum.map(1..100, fn _ -> AsnSocial.UUIDv7.generate() end)

    assert length(Enum.uniq(ids)) == 100

    for id <- ids do
      assert {:ok, _} = Ecto.UUID.cast(id)
      assert String.at(id, 14) == "7"
      assert String.at(id, 19) in ~w(8 9 a b)
    end
  end
end

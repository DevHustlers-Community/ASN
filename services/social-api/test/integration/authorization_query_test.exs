defmodule AsnSocial.AuthorizationQueryTest do
  use AsnSocial.DataCase, async: true

  alias AsnSocial.Repo

  test "authorization lookup can use the users primary-key index" do
    user_id = Ecto.UUID.generate()

    {:ok, %{rows: rows}} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL enable_seqscan = off")

        Repo.query!(
          "EXPLAIN (COSTS OFF) SELECT id, status, sessions_valid_after FROM users WHERE id = $1",
          [Ecto.UUID.dump!(user_id)]
        )
      end)

    assert Enum.any?(rows, fn [line] -> String.contains?(line, "users_pkey") end)
  end
end

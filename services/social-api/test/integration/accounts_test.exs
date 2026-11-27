defmodule AsnSocial.AccountsTest do
  use AsnSocial.DataCase, async: true

  alias AsnSocial.Accounts
  alias AsnSocial.Events.{Envelope, Outbox}
  alias AsnSocial.Repo

  test "creates a user and user.created event in one transaction" do
    assert {:ok, user} =
             Accounts.create_user(%{
               auth0_sub: "auth0|user-1",
               username: "asn-user",
               display_name: "ASN User"
             })

    event = Repo.get_by!(Outbox, type: "user.created", aggregate_id: user.id)
    assert event.aggregate_type == "user"
    assert event.aggregate_version == 1

    assert event.payload == %{
             "user_id" => user.id,
             "username" => "asn-user",
             "display_name" => "ASN User"
           }

    envelope = Envelope.from_outbox(event)
    assert envelope["event_id"] == event.id
    assert envelope["aggregate_id"] == user.id
    assert String.ends_with?(envelope["occurred_at"], "Z")
  end

  test "duplicate identity writes neither a user nor an event" do
    assert {:ok, _user} =
             Accounts.create_user(%{auth0_sub: "auth0|duplicate", username: "first-user"})

    assert {:error, changeset} =
             Accounts.create_user(%{auth0_sub: "auth0|duplicate", username: "second-user"})

    refute changeset.valid?
    assert Repo.aggregate(Outbox, :count) == 1
  end

  test "invalid registration writes nothing" do
    assert {:error, changeset} = Accounts.create_user(%{auth0_sub: "", username: ""})
    refute changeset.valid?
    assert Repo.aggregate(Outbox, :count) == 0
  end

  test "authorization returns only status and session cutoff" do
    cutoff = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, user} =
             Accounts.create_user(%{
               auth0_sub: "auth0|suspended",
               username: "suspended-user",
               status: :suspended,
               sessions_valid_after: cutoff
             })

    assert {:ok, view} = Accounts.authorization(user.id)

    assert view == %{
             user_id: user.id,
             status: "suspended",
             sessions_valid_after: DateTime.to_iso8601(cutoff)
           }

    assert {:error, :not_found} = Accounts.authorization(Ecto.UUID.generate())
    assert {:error, :not_found} = Accounts.authorization("not-a-uuid")
  end
end

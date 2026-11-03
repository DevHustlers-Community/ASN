defmodule AsnEventBroker.SecurityTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.Repo
  alias AsnEventBroker.Security
  alias AsnEventBroker.Security.ServiceCredential

  # Four authorization outcomes must be indistinguishable for valid, revoked,
  # expired, and unknown tokens: all non-valid inputs return the same
  # `{:error, :unauthorized}` shape with no distinguishing error or exit path
  # (issue #7).

  test "a valid token authorizes and returns the credential" do
    {:ok, issued} = Security.issue("test-service", [:publish])

    assert {:ok, %ServiceCredential{} = credential} =
             Security.authorize("Bearer " <> issued.token)

    assert credential.credential_id == issued.credential_id
    assert credential.service_name == "test-service"
    assert :publish in credential.scopes
  end

  test "a revoked token is unauthorized" do
    {:ok, issued} = Security.issue("test-service", [:publish])
    assert :ok = Security.revoke(issued.credential_id, issued.credential_id)

    assert {:error, :unauthorized} = Security.authorize("Bearer " <> issued.token)
  end

  test "an expired token is unauthorized" do
    {:ok, issued} = Security.issue("test-service", [:publish])

    past = DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.add(-3600)
    credential = Repo.get!(ServiceCredential, issued.credential_id)
    Ecto.Changeset.change(credential, expires_at: past) |> Repo.update!()

    assert {:error, :unauthorized} = Security.authorize("Bearer " <> issued.token)
  end

  test "an unknown token is unauthorized" do
    unknown = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    assert {:error, :unauthorized} = Security.authorize("Bearer " <> unknown)
  end

  test "missing, empty, and non-bearer authorization headers are unauthorized" do
    assert {:error, :unauthorized} = Security.authorize(nil)
    assert {:error, :unauthorized} = Security.authorize("")
    assert {:error, :unauthorized} = Security.authorize("token-without-scheme")
    assert {:error, :unauthorized} = Security.authorize("Basic nope")
    assert {:error, :unauthorized} = Security.authorize("Bearer ")
  end

  test "scope and event-type checks operate on the authorized credential" do
    {:ok, issued} =
      Security.issue("test-service", [:consume], allowed_event_types: ["report.created"])

    assert {:ok, credential} = Security.authorize("Bearer " <> issued.token)
    assert Security.scope_authorized?(credential, :consume)
    refute Security.scope_authorized?(credential, :publish)
    assert Security.event_type_authorized?(credential, "report.created")
    refute Security.event_type_authorized?(credential, "user.created")

    assert Security.event_type_authorized?(
             %{credential | allowed_event_types: nil},
             "user.created"
           )
  end
end

alias AsnChat.{Accounts.User, Devices, Repo}
alias AsnChat.Events.Outbox

{:ok, _started} = Application.ensure_all_started(:ecto_sql)
{:ok, _repo} = Repo.start_link()

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
user_id = AsnChat.UUIDv7.generate()

Repo.insert!(%User{
  id: user_id,
  username: "e2e-user",
  display_name: "E2E User",
  show_presence: true,
  plan: "free",
  source_version: 0,
  created_at: now,
  updated_at: now
})

{:ok, device, :created} =
  Devices.register_device(
    user_id,
    %{
      platform: :web,
      identity_key_public: <<0, 1, 2, 3>>,
      identity_key_fingerprint: String.duplicate("a", 32)
    },
    trace_id: "e2e-broker-relay"
  )

event =
  Repo.get_by!(Outbox,
    type: "chat.device.registered",
    aggregate_id: device.id
  )

unless event.aggregate_type == "device" and event.aggregate_version == 1 do
  raise "device event does not match the chat.device.registered v1 aggregate contract"
end

required_payload_keys = [
  "device_id",
  "user_id",
  "platform",
  "identity_key_fingerprint"
]

unless Enum.all?(required_payload_keys, &Map.has_key?(event.payload, &1)) do
  raise "device event payload is missing required public metadata"
end

IO.puts("E2E_EVENT_ID=#{event.id}")

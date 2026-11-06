defmodule AsnChat.Repo.Migrations.CreateChatDevices do
  use Ecto.Migration

  def up do
    create table(:chat_devices, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :user_id, references(:chat_users, type: :uuid), null: false
      add :platform, :text, null: false
      add :device_label, :varchar, size: 80
      add :identity_key_public, :bytea, null: false
      add :identity_key_fingerprint, :text, null: false
      add :registration_id, :integer
      add :status, :text, null: false, default: "active"
      add :created_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
    end

    create constraint(:chat_devices, :chat_devices_platform_check,
             check: "platform IN ('android', 'ios', 'web')"
           )

    create constraint(:chat_devices, :chat_devices_status_check,
             check: "status IN ('active', 'revoked', 'pending_verification')"
           )

    create index(:chat_devices, [:user_id, :status])

    # Registration idempotency: one active device row per user and
    # identity_key_fingerprint (architecture §3.7: public key changes are
    # identity changes, never silent overwrites).
    create index(:chat_devices, [:user_id, :identity_key_fingerprint],
             name: :chat_devices_user_active_fingerprint_index,
             unique: true,
             where: "status = 'active'"
           )

    # Composite FK target so `messages` can pin a device to its owner via
    # (sender_device_id, sender_id).
    create index(:chat_devices, [:id, :user_id],
             name: :chat_devices_id_user_id_index,
             unique: true
           )
  end

  def down do
    drop index(:chat_devices, [:id, :user_id], name: :chat_devices_id_user_id_index)

    drop index(:chat_devices, [:user_id, :identity_key_fingerprint],
           name: :chat_devices_user_active_fingerprint_index
         )

    drop index(:chat_devices, [:user_id, :status])

    drop constraint(:chat_devices, :chat_devices_status_check)
    drop constraint(:chat_devices, :chat_devices_platform_check)

    drop table(:chat_devices)
  end
end

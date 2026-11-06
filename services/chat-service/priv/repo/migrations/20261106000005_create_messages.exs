defmodule AsnChat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def up do
    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :conversation_id, references(:conversations, type: :uuid), null: false
      add :seq, :bigint, null: false
      add :sender_id, references(:chat_users, type: :uuid), null: false
      add :sender_device_id, references(:chat_devices, type: :uuid), null: false
      add :client_message_id, :uuid, null: false
      add :payload_kind, :text, null: false
      add :payload_mode, :text, null: false
      add :reply_to_id, :uuid
      add :is_user_activity, :boolean, null: false, default: true
      add :edited_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      # No `body` column, no `crypto_epoch`: the API surface and storage are
      # protocol-neutral; envelopes live in message_payloads.
      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create constraint(:messages, :messages_payload_kind_check,
             check: "payload_kind IN ('text', 'media', 'voice', 'system', 'control')"
           )

    create constraint(:messages, :messages_payload_mode_check,
             check: "payload_mode IN ('shared', 'per_device')"
           )

    # Logical uniqueness (architecture §3.9).
    create unique_index(:messages, [:conversation_id, :seq])
    create unique_index(:messages, [:sender_id, :client_message_id])
    create unique_index(:messages, [:id, :conversation_id])

    # History paging and changed-message sync cursors.
    create index(:messages, [:conversation_id, "seq DESC"],
             name: :messages_conversation_seq_desc_index
           )

    create index(:messages, [:conversation_id, :updated_at, :id],
             name: :messages_conversation_updated_at_id_index
           )

    # Ecto cannot express composite foreign keys; add them as raw SQL. The
    # referenced combinations are pinned by unique indexes created earlier in
    # this migration set (chat_devices.id+user_id; messages.id+conversation_id).
    execute(
      "ALTER TABLE messages ADD CONSTRAINT messages_sender_device_owner_fkey FOREIGN KEY " <>
        "(sender_device_id, sender_id) REFERENCES chat_devices (id, user_id)"
    )

    execute(
      "ALTER TABLE messages ADD CONSTRAINT messages_reply_in_conversation_fkey FOREIGN KEY " <>
        "(reply_to_id, conversation_id) REFERENCES messages (id, conversation_id)"
    )
  end

  def down do
    execute("ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_reply_in_conversation_fkey")

    execute("ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_sender_device_owner_fkey")

    drop index(:messages, [:conversation_id, :updated_at, :id],
           name: :messages_conversation_updated_at_id_index
         )

    drop index(:messages, [:conversation_id, "seq DESC"],
           name: :messages_conversation_seq_desc_index
         )

    drop unique_index(:messages, [:id, :conversation_id])
    drop unique_index(:messages, [:sender_id, :client_message_id])
    drop unique_index(:messages, [:conversation_id, :seq])

    drop constraint(:messages, :messages_payload_mode_check)
    drop constraint(:messages, :messages_payload_kind_check)

    drop table(:messages)
  end
end

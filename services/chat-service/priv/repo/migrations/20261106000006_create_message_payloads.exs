defmodule AsnChat.Repo.Migrations.CreateMessagePayloads do
  use Ecto.Migration

  def up do
    create table(:message_payloads, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :message_id, references(:messages, type: :uuid, on_delete: :delete_all), null: false

      add :revision_no, :integer, null: false, default: 1
      add :recipient_device_id, references(:chat_devices, type: :uuid)
      add :ciphertext, :bytea, null: false
      add :protocol_version, :integer, null: false

      add :created_at, :utc_datetime_usec, null: false
    end

    # Partial unique indexes exactly as architecture §3.10 (a flat unique
    # constraint cannot express the nullable recipient_device_id).
    create index(:message_payloads, [:message_id, :revision_no],
             name: :message_payloads_one_shared_per_revision,
             unique: true,
             where: "recipient_device_id IS NULL"
           )

    create index(:message_payloads, [:message_id, :revision_no, :recipient_device_id],
             name: :message_payloads_one_envelope_per_device_per_revision,
             unique: true,
             where: "recipient_device_id IS NOT NULL"
           )
  end

  def down do
    drop index(:message_payloads, [:message_id, :revision_no, :recipient_device_id],
           name: :message_payloads_one_envelope_per_device_per_revision
         )

    drop index(:message_payloads, [:message_id, :revision_no],
           name: :message_payloads_one_shared_per_revision
         )

    drop table(:message_payloads)
  end
end

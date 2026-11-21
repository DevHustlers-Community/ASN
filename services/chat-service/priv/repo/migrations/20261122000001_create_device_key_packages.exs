defmodule AsnChat.Repo.Migrations.CreateDeviceKeyPackages do
  use Ecto.Migration

  def up do
    create table(:device_key_packages, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :device_id, references(:chat_devices, type: :uuid), null: false
      add :key_package, :bytea, null: false
      add :key_package_sha256, :bytea, null: false
      add :ciphersuite, :integer, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :last_resort, :boolean, null: false, default: false
      add :consumed_at, :utc_datetime_usec
    end

    create constraint(:device_key_packages, :device_key_packages_ciphersuite_check,
             check: "ciphersuite BETWEEN 1 AND 65535"
           )

    create constraint(:device_key_packages, :device_key_packages_expiry_check,
             check: "expires_at > created_at"
           )

    # A 174764-character base64 body decodes to at most 131072 bytes, leaving
    # room for JSON overhead under the 256 KiB whole-body limit.
    create constraint(:device_key_packages, :device_key_packages_size_check,
             check: "octet_length(key_package) <= 131072"
           )

    create constraint(:device_key_packages, :device_key_packages_digest_check,
             check: "octet_length(key_package_sha256) = 32"
           )

    # One bundle may never be stored twice for a device; the future claim path
    # depends on this to hand a KeyPackage to exactly one initiator (ADR 0017).
    create unique_index(:device_key_packages, [:device_id, :key_package_sha256],
             name: :device_key_packages_device_digest_index
           )

    # Reserved for the deferred atomic claim path.
    create index(:device_key_packages, [:device_id, :expires_at],
             name: :device_key_packages_unconsumed_index,
             where: "consumed_at IS NULL"
           )
  end

  def down do
    drop index(:device_key_packages, [:device_id, :expires_at],
           name: :device_key_packages_unconsumed_index
         )

    drop index(:device_key_packages, [:device_id, :key_package_sha256],
           name: :device_key_packages_device_digest_index
         )

    drop constraint(:device_key_packages, :device_key_packages_digest_check)
    drop constraint(:device_key_packages, :device_key_packages_size_check)
    drop constraint(:device_key_packages, :device_key_packages_expiry_check)
    drop constraint(:device_key_packages, :device_key_packages_ciphersuite_check)

    drop table(:device_key_packages)
  end
end

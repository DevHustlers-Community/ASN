defmodule AsnSocial.Events.Outbox do
  @moduledoc "Transactional outbox rows for Social-owned domain events."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias AsnSocial.Repo

  @envelope_fields ~w(event_id type schema_version occurred_at aggregate_type aggregate_id aggregate_version trace_id payload)
  @type_pattern ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/
  @aggregate_type_pattern ~r/^[a-z][a-z0-9_]*$/

  @primary_key {:id, Ecto.UUID, autogenerate: false}

  schema "outbox_events" do
    field :type, :string
    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :aggregate_version, :integer
    field :schema_version, :integer
    field :occurred_at, :utc_datetime_usec
    field :payload, :map
    field :trace_id, :string
    field :created_at, :utc_datetime_usec
    field :published_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @spec record(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def record(envelope) when is_map(envelope) do
    attrs =
      envelope
      |> Map.take(@envelope_fields)
      |> Map.put("id", envelope["event_id"])

    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :type,
      :aggregate_type,
      :aggregate_id,
      :aggregate_version,
      :schema_version,
      :occurred_at,
      :payload,
      :trace_id
    ])
    |> validate_required([:type, :schema_version, :occurred_at, :payload])
    |> validate_event_id(envelope)
    |> validate_format(:type, @type_pattern)
    |> validate_format(:aggregate_type, @aggregate_type_pattern)
    |> validate_number(:schema_version, greater_than_or_equal_to: 1)
    |> validate_number(:aggregate_version, greater_than_or_equal_to: 1)
    |> validate_aggregate_fields()
    |> validate_payload_object()
    |> validate_envelope_fields(envelope)
    |> unique_constraint(:id, name: :outbox_events_pkey)
    |> unique_constraint(:aggregate_version,
      name: :outbox_events_aggregate_version_unique_index
    )
    |> put_created_at()
    |> Repo.insert()
  end

  @spec mark_published(String.t()) :: :ok
  def mark_published(id) do
    Repo.update_all(
      from(o in __MODULE__, where: o.id == ^id and is_nil(o.published_at)),
      set: [published_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]
    )

    :ok
  end

  defp validate_event_id(changeset, envelope) do
    if is_nil(envelope["event_id"]),
      do: add_error(changeset, :event_id, "can't be blank"),
      else: changeset
  end

  defp validate_aggregate_fields(changeset) do
    fields = [:aggregate_type, :aggregate_id, :aggregate_version]
    present = Enum.count(fields, &(get_field(changeset, &1) != nil))

    if present in [0, length(fields)] do
      changeset
    else
      add_error(
        changeset,
        :aggregate_type,
        "must be set together with aggregate_id and aggregate_version, or all three absent"
      )
    end
  end

  defp validate_payload_object(changeset) do
    case get_field(changeset, :payload) do
      nil -> changeset
      payload when is_map(payload) -> changeset
      _other -> add_error(changeset, :payload, "must be a JSON object")
    end
  end

  defp validate_envelope_fields(changeset, envelope) do
    case Map.keys(envelope) -- @envelope_fields do
      [] ->
        changeset

      unknown ->
        add_error(
          changeset,
          :base,
          "envelope contains unknown fields: #{Enum.map_join(unknown, ", ", &inspect/1)}"
        )
    end
  end

  defp put_created_at(changeset) do
    put_change(changeset, :created_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end
end

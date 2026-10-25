defmodule AsnEventBroker.Events.Envelope do
  @moduledoc """
  Canonical event envelope: validation and content hashing.

  Mirrors `contracts/events/common/event-envelope.schema.json`. The broker is
  opaque to the payload beyond this envelope validation; it never inspects
  business fields. `content_hash/1` is the publish-integrity anchor: it is
  computed over the complete canonical serialization of the envelope (JSON
  with recursively sorted keys), so a producer's key order can never turn an
  identical event into a 409.
  """

  import Ecto.UUID, only: [cast: 1]

  defstruct [
    :event_id,
    :type,
    :schema_version,
    :occurred_at,
    :aggregate_type,
    :aggregate_id,
    :aggregate_version,
    :trace_id,
    :payload
  ]

  @type t :: %__MODULE__{
          event_id: String.t(),
          type: String.t(),
          schema_version: pos_integer(),
          occurred_at: DateTime.t(),
          aggregate_type: String.t() | nil,
          aggregate_id: String.t() | nil,
          aggregate_version: pos_integer() | nil,
          trace_id: String.t() | nil,
          payload: map()
        }

  @known_fields ~w(event_id type schema_version occurred_at aggregate_type aggregate_id aggregate_version trace_id payload)
  @required_fields ~w(event_id type schema_version occurred_at payload)
  @aggregate_fields ~w(aggregate_type aggregate_id aggregate_version)

  @type_regex ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/
  @aggregate_type_regex ~r/^[a-z][a-z0-9_]*$/

  @spec validate(map()) :: {:ok, t()} | {:error, {:invalid_envelope, [String.t()]}}
  def validate(attrs) when is_map(attrs) do
    errors =
      Enum.concat([
        unknown_field_errors(attrs),
        missing_field_errors(attrs),
        field_errors(attrs),
        aggregate_errors(attrs)
      ])

    if errors == [] do
      {:ok, envelope(attrs)}
    else
      {:error, {:invalid_envelope, Enum.reverse(errors)}}
    end
  end

  def validate(_), do: {:error, {:invalid_envelope, ["envelope must be an object"]}}

  @doc "SHA-256 over the canonical (recursively key-sorted JSON) full envelope."
  @spec content_hash(t()) :: String.t()
  def content_hash(%__MODULE__{} = envelope) do
    %{
      "event_id" => envelope.event_id,
      "type" => envelope.type,
      "schema_version" => envelope.schema_version,
      "occurred_at" => DateTime.to_iso8601(envelope.occurred_at),
      "aggregate_type" => envelope.aggregate_type,
      "aggregate_id" => envelope.aggregate_id,
      "aggregate_version" => envelope.aggregate_version,
      "trace_id" => envelope.trace_id,
      "payload" => envelope.payload
    }
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(%{} = value) do
    %Jason.OrderedObject{
      values:
        value
        |> Enum.map(fn {key, inner} -> {to_string(key), canonical(inner)} end)
        |> Enum.sort()
    }
  end

  defp canonical(value), do: value

  defp envelope(attrs) do
    {:ok, occurred_at, _input_offset} = DateTime.from_iso8601(attrs["occurred_at"])

    %__MODULE__{
      event_id: attrs["event_id"],
      type: attrs["type"],
      schema_version: attrs["schema_version"],
      occurred_at: occurred_at,
      aggregate_type: attrs["aggregate_type"],
      aggregate_id: attrs["aggregate_id"],
      aggregate_version: attrs["aggregate_version"],
      trace_id: attrs["trace_id"],
      payload: attrs["payload"]
    }
  end

  defp unknown_field_errors(attrs) do
    attrs
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 in @known_fields))
    |> Enum.map(&("unknown field \"" <> &1 <> "\""))
  end

  defp missing_field_errors(attrs) do
    @required_fields
    |> Enum.reject(&present?(attrs[&1]))
    |> Enum.map(&("missing required field \"" <> &1 <> "\""))
  end

  defp field_errors(attrs) do
    Enum.concat([
      uuid_error("event_id", attrs["event_id"]),
      type_errors(attrs["type"]),
      version_errors("schema_version", attrs["schema_version"]),
      payload_errors(attrs["payload"]),
      trace_errors(attrs["trace_id"])
    ])
  end

  defp aggregate_errors(attrs) do
    values = Enum.map(@aggregate_fields, &attrs[&1])
    all_present? = Enum.all?(values, &present?/1)
    none_present? = Enum.all?(values, &is_nil/1)

    cond do
      none_present? ->
        []

      all_present? ->
        Enum.concat([
          uuid_error("aggregate_id", attrs["aggregate_id"]),
          aggregate_type_errors(attrs["aggregate_type"]),
          version_errors("aggregate_version", attrs["aggregate_version"])
        ])

      true ->
        ["aggregate_type, aggregate_id, and aggregate_version are all-or-none"]
    end
  end

  defp uuid_error(_field, nil), do: []

  defp uuid_error(field, value) do
    case cast(value) do
      {:ok, _} -> []
      :error -> ["field \"" <> field <> "\" is not a valid UUID"]
    end
  end

  defp type_errors(value) do
    if is_binary(value) and value =~ @type_regex,
      do: [],
      else: ["field \"type\" must match the dotted lowercase event type pattern"]
  end

  defp aggregate_type_errors(value) do
    if is_binary(value) and value =~ @aggregate_type_regex,
      do: [],
      else: ["field \"aggregate_type\" must match the lowercase aggregate pattern"]
  end

  defp version_errors(_field, value) when is_integer(value) and value >= 1, do: []
  defp version_errors(field, _), do: ["field \"" <> field <> "\" must be an integer >= 1"]

  defp payload_errors(value) when is_map(value), do: []
  defp payload_errors(_), do: ["field \"payload\" must be an object"]

  defp trace_errors(nil), do: []
  defp trace_errors(value) when is_binary(value) and value != "", do: []
  defp trace_errors(_), do: ["field \"trace_id\" must be a non-empty string"]

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end

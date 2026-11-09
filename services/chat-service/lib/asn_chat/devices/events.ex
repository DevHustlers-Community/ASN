defmodule AsnChat.Devices.Events do
  @moduledoc """
  Outbox envelope builders for device lifecycle events.

  The maps returned here are inputs for `AsnChat.Events.Outbox.record/1`; the
  wire envelope is rebuilt from the committed row at publish time. Payloads are
  deliberately minimal: no public key bytes, no device labels, and no private
  key material ever appears in a device event.
  """

  alias AsnChat.Devices.Device
  alias AsnChat.UUIDv7

  @doc """
  Builds the `chat.device.registered` event (aggregate version 1).
  """
  @spec registered(Device.t(), keyword()) :: map()
  def registered(device, opts \\ [])

  def registered(%Device{created_at: nil}, _opts) do
    raise ArgumentError, "registered/2 requires a device with created_at set"
  end

  def registered(%Device{} = device, opts) do
    envelope(
      device,
      "chat.device.registered",
      1,
      device.created_at,
      %{
        "device_id" => device.id,
        "user_id" => device.user_id,
        "platform" => Atom.to_string(device.platform),
        "identity_key_fingerprint" => device.identity_key_fingerprint
      },
      opts
    )
  end

  @doc """
  Builds the `chat.device.revoked` event (aggregate version 2).
  """
  @spec revoked(Device.t(), keyword()) :: map()
  def revoked(device, opts \\ [])

  def revoked(%Device{revoked_at: nil}, _opts) do
    raise ArgumentError, "revoked/2 requires a device with revoked_at set"
  end

  def revoked(%Device{} = device, opts) do
    envelope(
      device,
      "chat.device.revoked",
      2,
      device.revoked_at,
      %{
        "device_id" => device.id,
        "user_id" => device.user_id
      },
      opts
    )
  end

  defp envelope(device, type, aggregate_version, occurred_at, payload, opts) do
    %{
      "event_id" => UUIDv7.generate(),
      "type" => type,
      "schema_version" => 1,
      "occurred_at" => occurred_at,
      "aggregate_type" => "device",
      "aggregate_id" => device.id,
      "aggregate_version" => aggregate_version,
      "payload" => payload
    }
    |> put_trace_id(opts)
  end

  defp put_trace_id(envelope, opts) do
    case Keyword.get(opts, :trace_id) do
      trace_id when is_binary(trace_id) and trace_id != "" ->
        Map.put(envelope, "trace_id", trace_id)

      _other ->
        envelope
    end
  end
end

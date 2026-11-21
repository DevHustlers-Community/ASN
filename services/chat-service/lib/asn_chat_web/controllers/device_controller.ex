defmodule AsnChatWeb.DeviceController do
  @moduledoc """
  Device registration, listing, and revocation (contract slice 1).

  The controller maps HTTP to the `AsnChat.Devices` context; ownership and
  lifecycle rules stay in the context. `identity_key_public` is base64 on the
  wire and opaque bytes in storage. Responses contain public device metadata
  only.
  """

  use AsnChatWeb, :controller

  alias AsnChat.Devices
  alias AsnChatWeb.Problem

  @allowed_keys ~w(platform device_label identity_key_public identity_key_fingerprint)

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    {:ok, devices} = Devices.list_devices(conn.assigns.current_user_id)

    json(conn, %{items: Enum.map(devices, &device_view/1)})
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with :ok <- validate_keys(params),
         {:ok, attrs} <- decode_attrs(params),
         {:ok, device, result} <-
           Devices.register_device(conn.assigns.current_user_id, attrs) do
      conn
      |> put_status(if result == :created, do: 201, else: 200)
      |> json(device_view(device))
    else
      {:error, :identity_key_conflict} ->
        Problem.render(
          conn,
          409,
          "identity_key_conflict",
          "Identity key conflict",
          detail: "The fingerprint is already active with different public key bytes"
        )

      {:error, :user_not_found} ->
        Problem.render(conn, 403, "forbidden", "Forbidden")

      {:error, %Ecto.Changeset{} = changeset} ->
        Problem.render(conn, 422, "unprocessable", "Unprocessable request",
          errors: field_errors(changeset)
        )

      {:error, {:outbox_failed, _changeset}} ->
        Problem.render(conn, 503, "service_unavailable", "Service Unavailable")

      {:error, :invalid_request} ->
        Problem.render(conn, 400, "invalid_request", "Invalid request",
          detail: "Malformed request body"
        )
    end
  end

  @spec revoke(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def revoke(conn, %{"device_id" => device_id}) do
    case Devices.revoke_device(conn.assigns.current_user_id, device_id) do
      {:ok, device, _result} ->
        json(conn, device_view(device))

      {:error, :not_found} ->
        Problem.render(conn, 404, "not_found", "Not Found")

      {:error, %Ecto.Changeset{} = changeset} ->
        Problem.render(conn, 422, "unprocessable", "Unprocessable request",
          errors: field_errors(changeset)
        )

      {:error, {:outbox_failed, _changeset}} ->
        Problem.render(conn, 503, "service_unavailable", "Service Unavailable")
    end
  end

  defp validate_keys(params) when is_map(params) do
    if Map.keys(params) -- @allowed_keys == [] do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  defp validate_keys(_params), do: {:error, :invalid_request}

  defp decode_attrs(params) do
    with {:ok, public_key} <- decode_base64(params["identity_key_public"]) do
      {:ok,
       %{
         platform: params["platform"],
         device_label: params["device_label"],
         identity_key_public: public_key,
         identity_key_fingerprint: params["identity_key_fingerprint"]
       }}
    end
  end

  defp decode_base64(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, bytes} when byte_size(bytes) > 0 -> {:ok, bytes}
      _other -> {:error, :invalid_request}
    end
  end

  defp decode_base64(_value), do: {:error, :invalid_request}

  defp device_view(device) do
    %{
      device_id: device.id,
      platform: Atom.to_string(device.platform),
      device_label: device.device_label,
      identity_key_public: Base.encode64(device.identity_key_public),
      identity_key_fingerprint: device.identity_key_fingerprint,
      status: Atom.to_string(device.status),
      created_at: DateTime.to_iso8601(device.created_at),
      last_seen_at: iso8601(device.last_seen_at),
      revoked_at: iso8601(device.revoked_at)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp field_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _match, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{path: Atom.to_string(field), code: "invalid", detail: message}
      end)
    end)
  end
end

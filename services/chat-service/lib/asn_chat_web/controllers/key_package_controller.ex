defmodule AsnChatWeb.KeyPackageController do
  @moduledoc """
  Opaque KeyPackage upload and metadata listing (ADR 0017).

  The controller only maps HTTP to `AsnChat.Devices`; ownership, active-device
  status, digests, and limits stay in the context. KeyPackage bytes are opaque
  public protocol material, never plaintext.
  """

  use AsnChatWeb, :controller

  alias AsnChat.Devices
  alias AsnChatWeb.Problem

  @allowed_keys ~w(key_package ciphersuite expires_at last_resort)

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"device_id" => device_id} = params) do
    with :ok <- validate_keys(params),
         {:ok, attrs} <- decode_attrs(params) do
      case Devices.upload_key_package(
             conn.assigns.current_user_id,
             device_id,
             attrs.key_package,
             attrs.rest
           ) do
        {:ok, key_package} ->
          conn
          |> put_status(201)
          |> json(key_package_view(key_package))

        {:error, :not_found} ->
          Problem.render(conn, 404, "not_found", "Not Found")

        {:error, :duplicate} ->
          Problem.render(conn, 409, "conflict", "Conflict",
            detail: "This KeyPackage is already stored for the device"
          )

        {:error, :limit_reached} ->
          Problem.render(conn, 409, "conflict", "Conflict",
            detail: "The device has reached its unconsumed KeyPackage limit"
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          Problem.render(conn, 422, "unprocessable", "Unprocessable request",
            errors: field_errors(changeset)
          )
      end
    else
      {:error, :invalid_request} ->
        Problem.render(conn, 400, "invalid_request", "Invalid request",
          detail: "Malformed request body"
        )
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"device_id" => device_id}) do
    case Devices.list_key_packages(conn.assigns.current_user_id, device_id) do
      {:ok, key_packages} ->
        json(conn, %{items: Enum.map(key_packages, &key_package_view/1)})

      {:error, :not_found} ->
        Problem.render(conn, 404, "not_found", "Not Found")
    end
  end

  defp validate_keys(params) when is_map(params) do
    keys = Map.keys(params) -- ["device_id"]

    if keys -- @allowed_keys == [] do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  defp decode_attrs(params) do
    with {:ok, bytes} <- decode_base64(params["key_package"]),
         {:ok, expires_at} <- parse_expires_at(params["expires_at"]),
         {:ok, ciphersuite} <- parse_ciphersuite(params["ciphersuite"]),
         {:ok, last_resort} <- parse_last_resort(params) do
      {:ok,
       %{
         key_package: bytes,
         rest: %{
           ciphersuite: ciphersuite,
           expires_at: expires_at,
           last_resort: last_resort
         }
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

  defp parse_expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _other -> {:error, :invalid_request}
    end
  end

  defp parse_expires_at(_value), do: {:error, :invalid_request}

  defp parse_ciphersuite(value) when is_integer(value), do: {:ok, value}
  defp parse_ciphersuite(_value), do: {:error, :invalid_request}

  defp parse_last_resort(params) do
    case Map.get(params, "last_resort", false) do
      value when is_boolean(value) -> {:ok, value}
      _other -> {:error, :invalid_request}
    end
  end

  defp key_package_view(key_package) do
    %{
      id: key_package.id,
      device_id: key_package.device_id,
      ciphersuite: key_package.ciphersuite,
      created_at: DateTime.to_iso8601(key_package.created_at),
      expires_at: DateTime.to_iso8601(key_package.expires_at),
      last_resort: key_package.last_resort,
      consumed_at: iso8601(key_package.consumed_at)
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

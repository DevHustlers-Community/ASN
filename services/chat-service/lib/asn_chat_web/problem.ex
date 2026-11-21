defmodule AsnChatWeb.Problem do
  @moduledoc """
  RFC 9457 Problem Details responses with a stable Chat error code (ADR 0016).

  Every response carries `type`, `title`, `status`, `code`, and `request_id`.
  Optional `detail` and field-level `errors` are added when useful; stack
  traces, SQL, tokens, private keys, and plaintext never appear here.
  """

  import Plug.Conn

  @type opts :: [detail: String.t(), errors: [map()]]

  @spec render(Plug.Conn.t(), pos_integer(), String.t(), String.t(), opts()) :: Plug.Conn.t()
  def render(conn, status, code, title, opts \\ []) do
    body =
      %{
        type: "about:blank",
        title: title,
        status: status,
        code: code,
        request_id: request_id(conn)
      }
      |> put_unless_nil(:detail, Keyword.get(opts, :detail))
      |> put_unless_nil(:errors, Keyword.get(opts, :errors))

    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  @spec request_id(Plug.Conn.t()) :: String.t()
  def request_id(conn) do
    conn.assigns[:request_id] ||
      List.first(get_req_header(conn, "x-request-id")) ||
      "unknown"
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end

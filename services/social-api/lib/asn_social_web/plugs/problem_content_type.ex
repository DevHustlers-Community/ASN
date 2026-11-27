defmodule AsnSocialWeb.Plugs.ProblemContentType do
  @moduledoc "Keeps framework-level JSON errors on the RFC 9457 content type."

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      if conn.status >= 400 and json_content_type?(conn) do
        put_resp_header(conn, "content-type", "application/problem+json")
      else
        conn
      end
    end)
  end

  defp json_content_type?(conn) do
    case get_resp_header(conn, "content-type") do
      [value | _rest] -> String.starts_with?(value, "application/json")
      _other -> false
    end
  end
end

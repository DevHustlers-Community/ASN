defmodule AsnSocialWeb.Plugs.BodyLimit do
  @moduledoc """
  Rejects declared bodies above the REST contract limit before parsing.
  Plug.Parsers enforces the same limit for chunked bodies.
  """

  import Plug.Conn

  alias AsnSocialWeb.Problem

  @spec init(keyword()) :: non_neg_integer()
  def init(opts), do: Keyword.get(opts, :max_bytes, 262_144)

  @spec call(Plug.Conn.t(), non_neg_integer()) :: Plug.Conn.t()
  def call(conn, max_bytes) do
    case get_req_header(conn, "content-length") do
      [value | _rest] -> check_length(conn, value, max_bytes)
      _other -> conn
    end
  end

  defp check_length(conn, value, max_bytes) do
    case Integer.parse(value) do
      {size, ""} when size > max_bytes ->
        Problem.render(conn, 413, "payload_too_large", "Payload Too Large")

      _other ->
        conn
    end
  end
end

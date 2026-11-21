defmodule AsnChatWeb.Plugs.BodyLimit do
  @moduledoc """
  Rejects requests whose declared `Content-Length` exceeds the contract limit
  before `Plug.Parsers` reads or decodes the body (ADR 0016).

  `Plug.Parsers` is also configured with the same `:length` so chunked bodies
  without a `Content-Length` are bounded by the parser.
  """

  import Plug.Conn

  alias AsnChatWeb.Problem

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

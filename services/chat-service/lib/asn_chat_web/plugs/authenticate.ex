defmodule AsnChatWeb.Plugs.Authenticate do
  @moduledoc """
  Authenticates a bearer token and performs the authoritative authorization
  check (ADR 0016).

  On success it assigns `:current_user_id` and `:current_token`. Every failure
  is a Problem Details response: `401` for missing, malformed, expired, or
  revoked tokens; `403` for an inactive account or a missing scope; `503` with
  `code: service_unavailable` when the signing keys are unreachable, or `503`
  with `code: authorization_unavailable` when the authoritative account-status
  check cannot be completed. The check never falls back to a stale allow.
  """

  import Plug.Conn

  alias AsnChat.Auth.Token
  alias AsnChat.Authorization
  alias AsnChatWeb.Problem

  @spec init(keyword()) :: %{scopes: [String.t()]}
  def init(opts), do: %{scopes: Keyword.get(opts, :scopes, [])}

  @spec call(Plug.Conn.t(), %{scopes: [String.t()]}) :: Plug.Conn.t()
  def call(conn, %{scopes: required_scopes}) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, claims} <- Token.verify(token),
         :ok <- require_scopes(claims.scopes, required_scopes),
         :ok <- Authorization.authorize(claims.user_id, claims.issued_at) do
      conn
      |> assign(:current_user_id, claims.user_id)
      |> assign(:current_token, claims)
    else
      error -> handle_error(conn, error)
    end
  end

  @doc false
  @spec handle_error(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def handle_error(conn, {:error, :missing_token}),
    do: unauthorized(conn, "Missing bearer token")

  def handle_error(conn, {:error, :expired}), do: unauthorized(conn, "Expired bearer token")

  def handle_error(conn, {:error, :stale_token}), do: unauthorized(conn, "Token has been revoked")

  def handle_error(conn, {:error, :invalid_token}), do: unauthorized(conn, "Invalid bearer token")

  def handle_error(conn, {:error, :unknown_key}), do: unauthorized(conn, "Invalid bearer token")

  def handle_error(conn, {:error, :jwks_unavailable}), do: signing_keys_unavailable(conn)

  def handle_error(conn, {:error, :inactive}),
    do: Problem.render(conn, 403, "forbidden", "Forbidden")

  def handle_error(conn, {:error, :forbidden}),
    do: Problem.render(conn, 403, "forbidden", "Forbidden")

  def handle_error(conn, {:error, :unavailable}), do: authorization_unavailable(conn)

  def handle_error(conn, _other), do: unavailable(conn)

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [value | _rest] ->
        case String.split(value, " ", parts: 2) do
          [scheme, token] when token != "" ->
            if String.downcase(scheme) == "bearer" do
              {:ok, token}
            else
              {:error, :missing_token}
            end

          _other ->
            {:error, :missing_token}
        end

      _other ->
        {:error, :missing_token}
    end
  end

  defp require_scopes(_token_scopes, []), do: :ok

  defp require_scopes(token_scopes, required_scopes) do
    if Enum.all?(required_scopes, &(&1 in token_scopes)) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp unauthorized(conn, detail) do
    Problem.render(conn, 401, "unauthorized", "Unauthorized", detail: detail)
  end

  defp signing_keys_unavailable(conn) do
    Problem.render(conn, 503, "service_unavailable", "Service Unavailable",
      detail: "Signing keys are temporarily unavailable"
    )
  end

  defp authorization_unavailable(conn) do
    Problem.render(conn, 503, "authorization_unavailable", "Service Unavailable",
      detail: "Authorization is temporarily unavailable"
    )
  end

  defp unavailable(conn) do
    Problem.render(
      conn,
      503,
      "service_unavailable",
      "Service Unavailable",
      detail: "The service is temporarily unavailable"
    )
  end
end

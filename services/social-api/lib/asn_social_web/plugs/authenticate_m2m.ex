defmodule AsnSocialWeb.Plugs.AuthenticateM2M do
  @moduledoc "Validates Auth0 M2M tokens and the operation scope on internal routes."

  import Plug.Conn

  alias AsnSocial.Auth.Token
  alias AsnSocialWeb.Problem

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    config = Application.get_env(:asn_social, :auth, [])

    with {:ok, token} <- bearer_token(conn),
         {:ok, claims} <- Token.verify(token),
         :ok <- authorize_scope(claims, Keyword.get(config, :required_scope)) do
      assign(conn, :m2m_credential, claims)
    else
      {:error, :jwks_unavailable} ->
        Problem.render(conn, 503, "service_unavailable", "Service Unavailable")

      {:error, :missing_scope} ->
        Problem.render(conn, 403, "forbidden", "Forbidden")

      _ ->
        Problem.render(conn, 401, "unauthorized", "Unauthorized")
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_scope(%{scopes: scopes}, required) when is_binary(required) do
    if required in scopes, do: :ok, else: {:error, :missing_scope}
  end

  defp authorize_scope(_claims, _required), do: {:error, :missing_scope}
end

defmodule AsnSocialWeb.Controllers.AuthorizationController do
  use AsnSocialWeb, :controller

  alias AsnSocial.Accounts
  alias AsnSocialWeb.Problem

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"user_id" => user_id}) do
    case Accounts.authorization(user_id) do
      {:ok, view} ->
        json(conn, view)

      {:error, :not_found} ->
        Problem.render(conn, 404, "not_found", "Not Found")
    end
  end
end

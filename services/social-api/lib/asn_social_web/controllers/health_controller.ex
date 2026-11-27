defmodule AsnSocialWeb.Controllers.HealthController do
  use AsnSocialWeb, :controller

  alias AsnSocial.Repo
  alias AsnSocialWeb.Problem

  @spec live(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live(conn, _params), do: json(conn, %{status: "up"})

  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, %{num_rows: 1}} ->
        json(conn, %{status: "ready"})

      _ ->
        Problem.render(conn, 503, "not_ready", "Service Unavailable")
    end
  rescue
    _ -> Problem.render(conn, 503, "not_ready", "Service Unavailable")
  end
end

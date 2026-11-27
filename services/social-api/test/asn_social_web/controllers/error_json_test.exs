defmodule AsnSocialWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  test "renders RFC 9457 fallback errors" do
    assert AsnSocialWeb.ErrorJSON.render("404.json", %{request_id: "req-1"}) == %{
             type: "about:blank",
             title: "Not Found",
             status: 404,
             code: "not_found",
             request_id: "req-1"
           }

    assert AsnSocialWeb.ErrorJSON.render("500.json", %{}) == %{
             type: "about:blank",
             title: "Internal Server Error",
             status: 500,
             code: "internal_error",
             request_id: "unknown"
           }
  end
end

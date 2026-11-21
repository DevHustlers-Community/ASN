defmodule AsnChatWeb.ErrorJSONTest do
  use AsnChatWeb.ConnCase, async: true

  test "renders 404 as Problem Details" do
    assert %{
             type: "about:blank",
             status: 404,
             code: "not_found",
             title: "Not Found",
             request_id: "unknown"
           } = AsnChatWeb.ErrorJSON.render("404.json", %{})
  end

  test "renders 500 as Problem Details" do
    assert %{
             type: "about:blank",
             status: 500,
             code: "internal_error",
             title: "Internal Server Error",
             request_id: "unknown"
           } = AsnChatWeb.ErrorJSON.render("500.json", %{})
  end
end

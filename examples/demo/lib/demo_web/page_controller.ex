defmodule DemoWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  def home(conn, _params) do
    Phoenix.Controller.redirect(conn, to: "/login")
  end
end

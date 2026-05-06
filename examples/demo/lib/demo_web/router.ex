defmodule DemoWeb.Router do
  use DemoWeb, :router

  import PhoenixExRatatui.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {DemoWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  # We use a non-aliased `scope "/"` here on purpose. `tui_live`
  # generates a wrapper module at compile time using the calling
  # router's namespace, and Phoenix's scope-alias prepending would
  # double-prefix that name (turning `DemoWeb.Router.TuiLive_<hash>`
  # into `DemoWeb.DemoWeb.Router.TuiLive_<hash>`). Pass the `live`
  # routes' module names with explicit fully-qualified module
  # references instead.
  scope "/" do
    pipe_through(:browser)

    # Redirect root to /counter so opening localhost:4000 lands on
    # something visible.
    get("/", DemoWeb.PageController, :home)

    # 1. `tui_live` — full-page TUI with zero boilerplate. The macro
    #    generates a wrapping LiveView at compile time and registers
    #    it as a normal `live` route.
    tui_live("/counter", Demo.Counter)

    # 2. LiveComponent embedded inside a regular LiveView. The TUI
    #    lives alongside non-TUI content the parent LV controls.
    live("/admin", DemoWeb.AdminLive)
  end
end

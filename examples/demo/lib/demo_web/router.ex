defmodule DemoWeb.Router do
  use DemoWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {DemoWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", DemoWeb do
    pipe_through(:browser)

    # Redirect root to /login so opening localhost:4000 lands on the
    # demo's entry TUI.
    get("/", PageController, :home)

    # 1. Multi-route nav demo. /login → /counter or /admin via
    #    runtime intents (`{:navigate, "/path"}`). Same intent
    #    machinery powers /counter's `q → /login` "logout".
    live("/login", LoginLive)
    live("/counter", CounterLive)

    # 2. Unified-module LiveComponent embedded inside a regular
    #    LiveView. The TUI lives alongside non-TUI content the
    #    parent LV controls.
    live("/admin", AdminLive)
  end
end

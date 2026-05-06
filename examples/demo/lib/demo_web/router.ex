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

    # Redirect root to /counter so opening localhost:4000 lands on
    # something visible.
    get("/", PageController, :home)

    # 1. Unified-module full-page TUI. `DemoWeb.CounterLive` is both
    #    a `Phoenix.LiveView` and the `ExRatatui.App` driving it —
    #    mounted via Phoenix's regular `live/3`.
    live("/counter", CounterLive)

    # 2. Unified-module LiveComponent embedded inside a regular
    #    LiveView. The TUI lives alongside non-TUI content the
    #    parent LV controls.
    live("/admin", AdminLive)
  end
end

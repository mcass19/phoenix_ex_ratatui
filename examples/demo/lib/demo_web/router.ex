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

    # Three views — three different integration shapes:
    #
    # /        landing TUI (full-page LV, callbacks runtime)
    # /chat    rich-widget chat (full-page LV, callbacks runtime)
    # /admin   plain LV embedding a reducer-runtime LiveComponent
    #
    # All inter-page navigation flows through `phoenix_ex_ratatui`'s
    # runtime intents (`{:navigate, "/path"}` etc.), dispatched by
    # the LV macro into `Phoenix.LiveView.push_navigate/2` and friends.
    live("/", HomeLive)
    live("/chat", ChatLive)
    live("/admin", AdminLive)
  end
end

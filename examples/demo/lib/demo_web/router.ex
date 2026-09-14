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

    # Five views — different integration shapes:
    #
    # /              landing TUI (full-page LV, callbacks runtime)
    # /chat          rich-widget chat (full-page LV, callbacks runtime)
    # /admin         plain LV embedding a reducer-runtime LiveComponent
    # /coexistence   full-page TUI LV that ALSO defines its own
    #                handle_event/3 + handle_info/2 (HTML toolbar)
    # /cube          pixel regions: a spinning Viewport3D and a picsum.photos
    #                Image painted as images over the cell grid
    #
    # Most inter-page navigation flows through `phoenix_ex_ratatui`'s
    # runtime intents (`{:navigate, "/path"}` etc.), dispatched by
    # the LV macro into `Phoenix.LiveView.push_navigate/2` and friends.
    live("/", HomeLive)
    live("/chat", ChatLive)
    live("/admin", AdminLive)
    live("/coexistence", CoexistenceLive)
    live("/cube", CubeLive)
  end
end

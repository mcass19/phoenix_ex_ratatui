defmodule PhoenixExRatatui.TestRouter do
  @moduledoc """
  Phoenix router used by `PhoenixExRatatui.RouterTest` to exercise
  the `tui_live/3` macro end-to-end. Compiles two routes:

    * `tui_live "/tui_test", PhoenixExRatatui.TestApp` — defaults
    * `tui_live "/tui_admin", PhoenixExRatatui.TestApp, as: :admin` —
      with opts forwarded to `Phoenix.LiveView.Router.live/4`

  The generated wrapper modules show up under
  `PhoenixExRatatui.TestRouter.TuiLive_<hash>` and are excluded
  from `mix test --cover` (see mix.exs).
  """
  use Phoenix.Router

  import PhoenixExRatatui.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/" do
    pipe_through(:browser)

    tui_live("/tui_test", PhoenixExRatatui.TestApp)
    tui_live("/tui_admin", PhoenixExRatatui.TestApp, as: :admin)
  end
end

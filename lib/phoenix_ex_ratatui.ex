defmodule PhoenixExRatatui do
  @moduledoc """
  Run [`ExRatatui`](https://github.com/mcass19/ex_ratatui) apps inside a
  [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view).

  This package is the LiveView counterpart to
  [`kino_ex_ratatui`](https://github.com/mcass19/kino_ex_ratatui): a
  thin transport layer between an `ExRatatui.App` runtime and a
  browser, plus a JS hook that paints the rendered cell buffer
  directly into the DOM as `<span>` cells. No terminal emulator, no
  ANSI on the wire — just structured cell deltas pushed over the
  LiveView socket.

  Two entry points are planned:

    * `PhoenixExRatatui.LiveView` — full-page entry, mount via the
      router (`live "/tui", PhoenixExRatatui.LiveView, ...`).
    * `PhoenixExRatatui.LiveComponent` — drop a TUI inside an
      existing LiveView alongside other content.

  Both share a single `PhoenixExRatatui.Transport` (implementing
  `ExRatatui.Transport`) and a single `PhoenixExRatatui.Renderer.Html`
  for cell-diff JSON encoding.

  ## Status

  Pre-release. Public API is being built up chunk by chunk; until
  the first hex release, depend on this from a path checkout. See
  [CONTRIBUTING.md](contributing.html) for the local-dev story.
  """
end

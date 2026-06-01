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

  Two entry points are available:

    * `PhoenixExRatatui.LiveView` — full-page entry, mount via the
      router (`live "/tui", PhoenixExRatatui.LiveView, ...`).
    * `PhoenixExRatatui.LiveComponent` — drop a TUI inside an
      existing LiveView alongside other content.

  Both share a single `PhoenixExRatatui.Transport` (implementing
  `ExRatatui.Transport`) and a single `PhoenixExRatatui.Renderer.Html`
  for cell-diff JSON encoding.

  ## Wiring the JS hook

  The bundled JS hook lives in this package at
  `lib/assets/phoenix_ex_ratatui/main.js` and is exposed as a
  resolvable npm module via the package's top-level `package.json`.

  Add `phoenix_ex_ratatui` to `assets/package.json` alongside
  Phoenix's own JS deps (the `file:` path follows the same shape):

  ```json
  {
    "dependencies": {
      "phoenix": "file:../deps/phoenix",
      "phoenix_html": "file:../deps/phoenix_html",
      "phoenix_live_view": "file:../deps/phoenix_live_view",
      "phoenix_ex_ratatui": "file:../deps/phoenix_ex_ratatui"
    }
  }
  ```

  Run `npm install` (or whatever the asset-pipeline manager calls
  it) to symlink the package, then import the hook in
  `assets/js/app.js`:

  ```js
  import { Socket } from "phoenix"
  import { LiveSocket } from "phoenix_live_view"
  import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"

  const liveSocket = new LiveSocket("/live", Socket, {
    hooks: { PhoenixExRatatuiHook }
  })
  ```

  The hook handles cell-grid measurement, paint, key forwarding, and
  resize reporting. No additional CSS is required (the hook sets a
  monospace font, `white-space: pre`, and `line-height: 1` on its
  container as defaults; users override any of those via their own
  CSS).

  ## Installation

  Add `phoenix_ex_ratatui` to the deps in `mix.exs`:

  ```elixir
  {:phoenix_ex_ratatui, "~> 0.1"}
  ```

  It pulls in `ex_ratatui` (`~> 0.10`) transitively, which ships a
  precompiled NIF — no Rust toolchain required.
  """
end

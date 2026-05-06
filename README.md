# PhoenixExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_ex_ratatui.svg)](https://hex.pm/packages/phoenix_ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/phoenix_ex_ratatui)
[![CI](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/phoenix_ex_ratatui.svg)](https://github.com/mcass19/phoenix_ex_ratatui/blob/main/LICENSE)

Run [ExRatatui](https://github.com/mcass19/ex_ratatui) apps inside a [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view).

`PhoenixExRatatui` is the LiveView counterpart to [`kino_ex_ratatui`](https://github.com/mcass19/kino_ex_ratatui): a thin transport that pipes the runtime's rendered **cell buffer** to the browser, where a small JS hook paints cells directly into the DOM as `<span>` elements. No terminal emulator, no ANSI on the wire — just structured cell deltas over the LiveView socket. Phones get real touch events.

## Three ways to mount a TUI

Pick the one that matches your project layout:

```elixir
# 1. One-line full-page route. Lowest boilerplate.
defmodule MyAppWeb.Router do
  use Phoenix.Router
  import PhoenixExRatatui.Router

  scope "/", MyAppWeb do
    pipe_through :browser
    tui_live "/tui", MyApp.Tui
  end
end
```

```elixir
# 2. Explicit full-page LiveView. Use when you need to override
# mount/3, render/1, or thread per-route assigns from the session.
defmodule MyAppWeb.MyTuiLive do
  use PhoenixExRatatui.LiveView, app: MyApp.Tui
end

# router:
live "/tui", MyAppWeb.MyTuiLive
```

```elixir
# 3. Embedded LiveComponent. Use when the TUI lives alongside other
# content in your own LiveView (admin dashboards, dev consoles, etc.).
defmodule MyAppWeb.AdminLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <h1>Admin Dashboard</h1>
    <.live_component
      module={PhoenixExRatatui.LiveComponent}
      id="admin-tui"
      app={MyApp.AdminTui}
    />
    <p>Other admin content</p>
    """
  end
end
```

All three drive the same `PhoenixExRatatui.Transport` underneath — a `CellSession` + `ExRatatui.Server` pair that ships rendered cell diffs to the browser as `phx_ex_ratatui:render` events.

## Wiring the JS hook

The bundled hook lives at `lib/assets/phoenix_ex_ratatui/main.js`. Wire it into your LiveSocket:

```js
// assets/js/app.js
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { PhoenixExRatatuiHook } from "../../deps/phoenix_ex_ratatui/lib/assets/phoenix_ex_ratatui/main.js"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { PhoenixExRatatuiHook }
})
```

The hook handles cell measurement, paint, key forwarding, and resize reporting. It sets sensible defaults on the container (monospace font, `white-space: pre`, `line-height: 1`) only if you haven't supplied your own, so you can theme freely with CSS.

## Status

**Pre-release.** This package depends on a `:cell_session` transport tag in `ex_ratatui` that lives in ex_ratatui's `[Unreleased]` CHANGELOG section. Until that release ships, depend on `phoenix_ex_ratatui` from a path checkout:

```elixir
# in your mix.exs
{:phoenix_ex_ratatui, path: "../phoenix_ex_ratatui"},
{:ex_ratatui, path: "../ex_ratatui", override: true}
```

After the next ex_ratatui release lands, this flips to:

```elixir
{:phoenix_ex_ratatui, "~> 0.1"}
```

## Quick links

- [Getting Started guide](guides/getting_started.md) — extended walkthrough of all three APIs
- [`examples/demo/`](examples/demo/) — minimal Phoenix app exercising `tui_live` and `LiveComponent` side-by-side
- [`PhoenixExRatatui.LiveView`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.LiveView.html) — the macro
- [`PhoenixExRatatui.LiveComponent`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.LiveComponent.html) — the embeddable
- [`PhoenixExRatatui.Router`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.Router.html) — the `tui_live` macro
- [`PhoenixExRatatui.Telemetry`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.Telemetry.html) — `:telemetry` events catalogue + `Telemetry.Metrics` wiring example
- [CONTRIBUTING.md](CONTRIBUTING.md) — local-dev setup

## Contributing

PhoenixExRatatui is built on [ExRatatui](https://github.com/mcass19/ex_ratatui), a general-purpose terminal UI library for Elixir. If you're interested in improving the underlying rendering, widgets, or layout engine, contributions to ExRatatui are very welcome too.

## License

MIT — see [LICENSE](LICENSE).

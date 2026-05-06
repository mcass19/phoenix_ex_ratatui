# PhoenixExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_ex_ratatui.svg)](https://hex.pm/packages/phoenix_ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/phoenix_ex_ratatui)
[![CI](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/phoenix_ex_ratatui.svg)](https://github.com/mcass19/phoenix_ex_ratatui/blob/main/LICENSE)

Run [ExRatatui](https://github.com/mcass19/ex_ratatui) apps inside a [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view).

`PhoenixExRatatui` is the LiveView counterpart to [`kino_ex_ratatui`](https://github.com/mcass19/kino_ex_ratatui): a thin transport that pipes the runtime's rendered **cell buffer** to the browser, where a small JS hook paints cells directly into the DOM as `<span>` elements. No terminal emulator, no ANSI on the wire — just structured cell deltas over the LiveView socket. Phones get real touch events.

## Two ways to mount a TUI

Both shapes are **unified modules** — the same module is both a Phoenix LiveView/LiveComponent and the `ExRatatui.App` driving it. The macro auto-generates a hidden `Module.Runtime` proxy that conforms to `ExRatatui.App` by delegating to your `tui_*` callbacks.

```elixir
# 1. Full-page TUI route — same module is both the Phoenix.LiveView
#    and the App.
defmodule MyAppWeb.MyTuiLive do
  use PhoenixExRatatui.LiveView

  def tui_mount(_opts), do: {:ok, %{count: 0}}

  def tui_render(state, frame) do
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Widgets.Paragraph
    [{%Paragraph{text: "Count: #{state.count}"},
      %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  def tui_handle_event(%ExRatatui.Event.Key{code: "+"}, state),
    do: {:noreply, %{state | count: state.count + 1}}

  def tui_handle_event(%ExRatatui.Event.Key{code: "q"}, state),
    do: {:stop, state}

  def tui_handle_event(_event, state), do: {:noreply, state}
end

# In your router (no special macro):
live "/tui", MyAppWeb.MyTuiLive
```

```elixir
# 2. Embedded LiveComponent — same shape, drops a TUI inside an
#    existing LiveView's render alongside non-TUI content.
defmodule MyAppWeb.AdminCounterPanel do
  use PhoenixExRatatui.LiveComponent

  def tui_mount(_opts), do: {:ok, %{n: 0}}
  def tui_render(state, frame), do: # ...
  def tui_handle_event(_event, state), do: {:noreply, state}
end

defmodule MyAppWeb.AdminLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <h1>Admin Dashboard</h1>
    <.live_component module={MyAppWeb.AdminCounterPanel} id="admin-tui" />
    <p>Other admin content</p>
    """
  end
end
```

Both drive the same `PhoenixExRatatui.Transport` underneath — a `CellSession` + `ExRatatui.Server` pair that ships rendered cell diffs to the browser as `phx_ex_ratatui:render` events.

## Threading socket data into the App

LiveView assigns and TUI state live in different processes. The `tui_mount_opts/1` callback is the bridge — it receives the LiveView socket and returns the keyword list passed as `opts` to `tui_mount/1`:

```elixir
defmodule MyAppWeb.AdminTui do
  use PhoenixExRatatui.LiveView

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    {:ok, socket} = super(nil, nil, socket)
    {:ok, assign(socket, :user_id, session["user_id"])}
  end

  def tui_mount_opts(socket), do: [user_id: socket.assigns.user_id]

  def tui_mount(opts), do: {:ok, %{user_id: opts[:user_id]}}
end
```

## Wiring the JS hook

The hook is resolved as a normal npm module. Add it to your `assets/package.json` alongside Phoenix's own JS deps:

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

Run `npm install` (or `cd assets && npm install`), then import the hook in your `assets/js/app.js`:

```js
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"

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

- [Getting Started guide](guides/getting_started.md) — extended walkthrough of both APIs
- [`examples/demo/`](examples/demo/) — minimal Phoenix app with the unified LV and LC side-by-side
- [`PhoenixExRatatui.LiveView`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.LiveView.html) — the full-page macro
- [`PhoenixExRatatui.LiveComponent`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.LiveComponent.html) — the embeddable macro
- [`PhoenixExRatatui.Telemetry`](https://hexdocs.pm/phoenix_ex_ratatui/PhoenixExRatatui.Telemetry.html) — `:telemetry` events catalogue + `Telemetry.Metrics` wiring example
- [CONTRIBUTING.md](CONTRIBUTING.md) — local-dev setup

## Contributing

PhoenixExRatatui is built on [ExRatatui](https://github.com/mcass19/ex_ratatui), a general-purpose terminal UI library for Elixir. If you're interested in improving the underlying rendering, widgets, or layout engine, contributions to ExRatatui are very welcome too.

## License

MIT — see [LICENSE](LICENSE).

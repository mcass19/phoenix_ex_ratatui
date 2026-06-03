# PhoenixExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_ex_ratatui.svg)](https://hex.pm/packages/phoenix_ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/phoenix_ex_ratatui)
[![CI](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/phoenix_ex_ratatui.svg)](https://github.com/mcass19/phoenix_ex_ratatui/blob/main/LICENSE)

Run [ExRatatui](https://github.com/mcass19/ex_ratatui) apps inside a [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view).

![PhoenixExRatatui Demo](https://raw.githubusercontent.com/mcass19/phoenix_ex_ratatui/main/.github/demo.gif)

`PhoenixExRatatui` is a thin transport that pipes the runtime's rendered **cell buffer** to the browser, where a small JS hook paints cells directly into the DOM as `<span>` elements. No terminal emulator, no ANSI on the wire — just structured cell deltas over the LiveView socket.

## Features

- **Two unified-module APIs** — `use PhoenixExRatatui.LiveView` for a full-page TUI route, `use PhoenixExRatatui.LiveComponent` to embed a TUI inside an existing LiveView. The same module is both the Phoenix component and the `ExRatatui.App` driving it; a hidden `Module.Runtime` proxy bridges the two `handle_info/2` arities.
- **Callback and reducer runtimes** — `runtime: :reducer` opts into command/subscription-driven apps (`tui_init/1` + `tui_update/2` + `tui_subscriptions/1`); the default `:callbacks` runtime uses `tui_mount/1` + `tui_handle_event/2` + `tui_handle_info/2`.
- **Cell-diff rendering over the socket** — the rendered cell buffer ships as a structured `%{width, height, ops}` payload of `<span>`-cell deltas. Arrays not objects, to roughly halve the wire size on full frames.
- **Tiny, dependency-free JS hook** — ~4KB minified (vs. xterm.js's ~250KB). Measures the cell box, paints diffs by direct `cells[row][col]` lookup, forwards `keydown` as input events, and re-reports size via `ResizeObserver`.
- **Inter-page navigation via runtime intents** — return `{:navigate, "/path"}`, `:patch`, or `:redirect` (internal or external) from any handler; the macro dispatches through `push_navigate/2` and friends.
- **Auto-focus on full-page TUIs** — keystrokes flow without clicking the grid first. Embedded components deliberately don't steal focus.
- **`:telemetry` integration** — transport connect/disconnect spans, a per-frame render span, and input-forward events, layered above the events `ex_ratatui` already emits.
- **Full color and modifiers** — named, RGB, and 256-color indexed; bold, italic, underline, and more, inherited straight from ExRatatui.

## Examples

The [`examples/demo/`](https://github.com/mcass19/phoenix_ex_ratatui/tree/main/examples/demo) Phoenix app showcases the unified LV and LC side-by-side:

| View | Route | Demonstrates |
|------|-------|--------------|
| Home | `/` | Full-page LiveView, reducer runtime, navigation intents |
| Chat | `/chat` | Full-page LiveView, callbacks runtime, Markdown/Textarea/Throbber/slash-command popup/scrollback |
| Admin | `/admin` | An embedded reducer-runtime `LiveComponent` with a live Gauge/Table system monitor |

Run it with `mix deps.get && mix phx.server` from inside `examples/demo/`.

## Ecosystem

- [ex_ratatui](https://github.com/mcass19/ex_ratatui) — The core terminal UI library this builds on.
- [kino_ex_ratatui](https://github.com/mcass19/kino_ex_ratatui) — Run TUIs inside [Livebook](https://livebook.dev) notebooks.

## Installation

Add `phoenix_ex_ratatui` to the deps in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_ex_ratatui, "~> 0.1"}
  ]
end
```

Then fetch:

```sh
mix deps.get
```

### Prerequisites

- Elixir 1.17+
- Phoenix LiveView 1.1+

### Wiring the JS hook

The hook is resolved as a normal npm module. Add it to `assets/package.json` alongside Phoenix's own JS deps:

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

Run `npm install` (or `cd assets && npm install`), then import the hook in `assets/js/app.js`:

```js
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { PhoenixExRatatuiHook }
})
```

The hook sets sensible defaults on the container (monospace font, `white-space: pre`, `line-height: 1`) only when they aren't already supplied, so the grid stays themeable with CSS.

## Quick Start

Both shapes are **unified modules** — the same module is both a Phoenix LiveView/LiveComponent and the `ExRatatui.App` driving it. The macro auto-generates a hidden `Module.Runtime` proxy that conforms to `ExRatatui.App` by delegating to the `tui_*` callbacks.

### Full-page TUI route

```elixir
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

# In the router (no special macro):
live "/tui", MyAppWeb.MyTuiLive
```

### Embedded LiveComponent

```elixir
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

## How It Works

```
┌─────────────────┐   tui_* callbacks   ┌──────────────────────┐
│  Your module    │ ◀────────────────── │  Module.Runtime      │  (hidden proxy,
│  (LiveView/LC)  │                     │  conforms to App     │   generated by macro)
└────────┬────────┘                     └──────────┬───────────┘
         │                                         │
         │ PhoenixExRatatui.Transport              │ ExRatatui.Server
         ▼                                         ▼
   CellSession  ──── %CellSession.Diff{} ────▶  Renderer.Html
                                                   │
                          push_event("phx_ex_ratatui:render", payload)
                                                   ▼
                                       JS hook paints <span> cells
   browser keydown ──── "phx_ex_ratatui:input" ────▶ back into the runtime
```

A `CellSession` plus a linked ExRatatui.Server drive the module. On each render the server hands a `%CellSession.Diff{}` to the transport, which forwards it to the LiveView; `PhoenixExRatatui.Renderer.Html` encodes it to a JSON-friendly payload and `push_event/3`s it to the browser. The hook paints the deltas and forwards keystrokes back as `phx_ex_ratatui:input` events. Because the `Server` is linked to the LiveView process, teardown is deterministic — when the LiveView exits, the session closes and disconnect telemetry fires.

## Inter-page navigation via runtime intents

A TUI can navigate to another route by emitting a runtime intent from any handler:

```elixir
def tui_handle_event(%Key{code: "enter"}, state) do
  {:noreply, state, intents: [{:navigate, "/dashboard"}]}
end

def tui_handle_event(%Key{code: "q"}, state) do
  {:noreply, state, intents: [{:redirect, "/login"}]}
end
```

Recognised intent shapes:

| Intent | Effect |
|---|---|
| `{:navigate, "/path"}` | `Phoenix.LiveView.push_navigate/2` |
| `{:patch, "/path"}` | `Phoenix.LiveView.push_patch/2` |
| `{:redirect, "/path"}` | `Phoenix.LiveView.redirect/2` (internal) |
| `{:redirect, [external: "https://…"]}` | `redirect/2` to an external URL |

Unrecognised intents are dropped (logged at warning) so a TUI stays portable across consumers — return whatever the runtime understands and the LV ignores the rest.

For the embeddable `LiveComponent`, intents bubble up to the parent LV via `send/2` (Phoenix LV forbids redirects from inside `LiveComponent.update/2`). Add this clause to the parent LV:

```elixir
def handle_info({:phoenix_ex_ratatui, :intent, intent}, socket) do
  {:noreply, PhoenixExRatatui.LiveView.dispatch_intent(socket, intent)}
end
```

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

## Guides

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/getting_started.md) | Extended walkthrough of both the full-page and embedded APIs, the JS hook wiring, and the typical project structure |
| [Telemetry](guides/telemetry.md) | `:telemetry` events for transport, render, input, and intents — logging and `Telemetry.Metrics` |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

PhoenixExRatatui is built on [ExRatatui](https://github.com/mcass19/ex_ratatui), a general-purpose terminal UI library for Elixir. If you're interested in improving the underlying rendering, widgets, or layout engine, contributions to ExRatatui are very welcome as well.

## License

MIT — see [LICENSE](https://github.com/mcass19/phoenix_ex_ratatui/blob/main/LICENSE).

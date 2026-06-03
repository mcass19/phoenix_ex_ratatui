# Getting Started

This guide walks through wiring a TUI into a Phoenix LiveView from
scratch, then explains the two integration APIs and when to reach
for each.

## Project setup

`phoenix_ex_ratatui` runs alongside the rest of a normal Phoenix
project — you don't need any special generator. Add the deps:

```elixir
# mix.exs
defp deps do
  [
    # …
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 1.1"},
    {:phoenix_ex_ratatui, "~> 0.1"}
    # `ex_ratatui` is pulled in transitively
  ]
end
```

Wire the JS hook. `phoenix_ex_ratatui` ships a top-level
`package.json`, so you import it like any other npm module. Add it
to your `assets/package.json`:

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

Then `cd assets && npm install` to symlink it, and import the hook
in your `assets/js/app.js`:

```js
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { PhoenixExRatatuiHook }
})

liveSocket.connect()
```

That's the only client-side wiring. The hook auto-discovers each
TUI's container by `phx-hook="PhoenixExRatatuiHook"` and handles cell
measurement, paint, keypress forwarding, and resize observation
itself.

## The unified-module pattern

Both APIs (`PhoenixExRatatui.LiveView` and
`PhoenixExRatatui.LiveComponent`) are **unified modules**: the same
module is both the Phoenix LiveView/LiveComponent AND the
`ExRatatui.App` driving it.

The macro doesn't fight Phoenix's `handle_info/2` callback (which
takes a socket) and the App's `handle_info/2` callback (which takes
App state) — they have the same name and arity but different
semantics. Instead, the macro auto-generates a hidden
`Module.Runtime` proxy via `@after_compile` that conforms to
`ExRatatui.App` by delegating to a small set of `tui_*` callbacks on
your module:

| Callback | Purpose | Default |
|---|---|---|
| `tui_mount(opts)` | Initialise App state | `{:ok, %{}}` |
| `tui_render(state, frame)` | Produce widgets | `[]` |
| `tui_handle_event(event, state)` | Handle a key/mouse/resize event | `{:noreply, state}` |
| `tui_handle_info(msg, state)` | Handle a non-terminal message (PubSub, send) | `{:noreply, state}` |
| `tui_terminate(reason, state)` | Cleanup on shutdown | `:ok` |
| `tui_mount_opts(socket)` | Bridge socket assigns into `tui_mount/1` | `[]` |

All are overridable; you implement what you need. Phoenix's regular
LV/LC callbacks (`mount/3`, `render/1`, `handle_event/3`, etc.)
remain available and overridable through the same `defoverridable`
mechanism.

## Two ways to mount a TUI

### Option A — Full-page TUI route (`PhoenixExRatatui.LiveView`)

When the page IS a TUI, write a unified module and mount it through
the router's regular `live/3` macro:

```elixir
defmodule MyAppWeb.CounterLive do
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  def tui_mount(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [
      {%Paragraph{
         text: "Count: #{state.n}\n\n+ increment   - decrement   q quit",
         block: %Block{title: " counter ", borders: [:all]}
       },
       %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
    ]
  end

  def tui_handle_event(%Key{code: "+"}, s), do: {:noreply, %{s | n: s.n + 1}}
  def tui_handle_event(%Key{code: "-"}, s), do: {:noreply, %{s | n: s.n - 1}}
  def tui_handle_event(%Key{code: "q"}, s), do: {:stop, s}
  def tui_handle_event(_, s), do: {:noreply, s}
end
```

In the router:

```elixir
scope "/", MyAppWeb do
  pipe_through :browser
  live "/counter", CounterLive
end
```

That's the full integration. The `@after_compile` hook generates
`MyAppWeb.CounterLive.Runtime` automatically — you never reference
it directly.

#### Threading socket data into the App

When you need to pass per-connection context (current user, session,
URL params) from the LiveView mount into `tui_mount/1`, override
`tui_mount_opts/1`:

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

`super/3` delegates to the macro's default `mount/3` (which sets up
internal assigns and trap_exit); you layer your own assigns on top
afterward. `tui_mount_opts/1` reads them off the socket and returns
the keyword list that becomes `opts` in `tui_mount/1`.

### Option B — Embedded TUI (`PhoenixExRatatui.LiveComponent`)

When the page is a regular Phoenix dashboard with a TUI sidebar, dev
console, or modal — anything where the TUI lives alongside other
content the user already controls — write a unified `LiveComponent`:

```elixir
defmodule MyAppWeb.SystemMonitorPanel do
  use PhoenixExRatatui.LiveComponent

  def tui_mount(_opts), do: {:ok, %{cpu: 0.0, mem: 0.0}}

  def tui_render(state, frame) do
    # widgets…
  end

  def tui_handle_event(_event, state), do: {:noreply, state}
end
```

Embed it inside any LiveView's render:

```elixir
defmodule MyAppWeb.AdminLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :recent_orders, fetch_recent_orders())}
  end

  def render(assigns) do
    ~H"""
    <h1>Admin Dashboard</h1>

    <div class="grid grid-cols-2 gap-4">
      <div>
        <h2>Recent Orders</h2>
        <ul>
          <li :for={order <- @recent_orders}>{order.id} — {order.total}</li>
        </ul>
      </div>

      <div>
        <h2>Live System Monitor</h2>
        <.live_component module={MyAppWeb.SystemMonitorPanel} id="admin-tui" />
      </div>
    </div>
    """
  end
end
```

The TUI's diff stream routes through `Phoenix.LiveView.send_update/3`
into the component's `update/2` (LiveComponents have no `handle_info`
— they share the parent LV's process). Everything else is identical
to the full-page path.

## Inter-page navigation

A TUI can request navigation to another LV route by returning a list of
runtime intents from any handler. The intents flow through
`ExRatatui.Server`'s intent writer into the LV, which dispatches them
to `Phoenix.LiveView.push_navigate/2` (and its siblings):

```elixir
defmodule MyAppWeb.LoginTui do
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key

  def tui_mount(_opts), do: {:ok, %{}}

  def tui_render(_state, _frame), do: # …

  # Press <enter> → push_navigate to /dashboard
  def tui_handle_event(%Key{code: "enter"}, state) do
    {:noreply, state, intents: [{:navigate, "/dashboard"}]}
  end

  def tui_handle_event(_, state), do: {:noreply, state}
end
```

Recognised intent shapes:

| Intent | Effect |
|---|---|
| `{:navigate, "/path"}` | `Phoenix.LiveView.push_navigate(socket, to: path)` |
| `{:patch, "/path"}` | `Phoenix.LiveView.push_patch(socket, to: path)` |
| `{:redirect, "/path"}` | `Phoenix.LiveView.redirect(socket, to: path)` |
| `{:redirect, [external: "https://…"]}` | external redirect |

Unrecognised intents are dropped (logged at warning level), so a TUI
that returns an intent the host doesn't know how to handle stays
alive instead of crashing.

### Embedded LiveComponent navigation

Phoenix LV forbids redirects from inside `LiveComponent.update/2`,
so when the embedded TUI emits a navigation intent the LiveComponent
sends it to its parent LV process via `send/2` and the parent
dispatches. Add this clause to the parent LV:

```elixir
def handle_info({:phoenix_ex_ratatui, :intent, intent}, socket) do
  {:noreply, PhoenixExRatatui.LiveView.dispatch_intent(socket, intent)}
end
```

If the parent is itself a `PhoenixExRatatui.LiveView`, the clause is
generated for you and you don't need to do anything.

### Stop-then-redirect

Intents from `{:stop, state, intents: ...}` transitions fire **before**
the runtime server exits, so a TUI can return
`{:stop, state, intents: [{:redirect, "/login"}]}` from a "logout" key
and trust the redirect reaches the LV before the server's EXIT signal
propagates.

## Decision matrix

| Use | When |
|---|---|
| `use PhoenixExRatatui.LiveView` | The whole page IS the TUI |
| `use PhoenixExRatatui.LiveComponent` | The page contains the TUI alongside other content (admin panels, dashboards, modals, dev tooling) |

Both are fully production-ready. The decision is purely about fit
with your project layout.

## Telemetry

Both integrations emit the same `:telemetry` events, one layer above the events `ex_ratatui` already emits. Attach the default logger in dev with `PhoenixExRatatui.Telemetry.attach_default_logger(level: :info)`, or wire `Telemetry.Metrics` for production dashboards. The [Telemetry guide](telemetry.md) covers the full event tree, a `Telemetry.Metrics` example, and how the two event layers pair up.

## What about ANSI / xterm.js / a real terminal in a browser?

That's [`kino_ex_ratatui`](https://github.com/mcass19/kino_ex_ratatui)
— same author, same parent library, but it's built around xterm.js
and is the right pick when you want a real terminal emulator in the
page.

`phoenix_ex_ratatui` is deliberately different: cells are pushed
directly to the DOM as styled `<span>`s. The advantages are that
the bundle is tiny (~4KB minified, no third-party deps), phones
get real touch events, and the cell grid is just HTML — themeable
with CSS, accessible to screen readers, copy/pasteable. The
trade-off is no scrollback, no shell semantics, no ANSI alt-screen
— if your TUI was relying on those, `kino_ex_ratatui` (or running
the App over SSH) is the right call.

## Where to next?

- Browse the full module reference for [`PhoenixExRatatui.LiveView`](`PhoenixExRatatui.LiveView`),
  [`PhoenixExRatatui.LiveComponent`](`PhoenixExRatatui.LiveComponent`),
  and [`PhoenixExRatatui.Transport`](`PhoenixExRatatui.Transport`)
- Read the [`examples/demo/`](https://github.com/mcass19/phoenix_ex_ratatui/tree/main/examples/demo)
  README and source for a working minimal Phoenix app that uses
  both unified APIs side-by-side
- For the upstream cell-extraction primitive, see
  [`ExRatatui.CellSession`](https://hexdocs.pm/ex_ratatui/ExRatatui.CellSession.html)

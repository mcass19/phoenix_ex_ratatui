# Getting Started

This guide walks through wiring an `ExRatatui.App` into a Phoenix
LiveView from scratch, then explains the three integration APIs and
when to reach for each.

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

Wire the JS hook into your `LiveSocket`. The hook lives in this
package's bundled assets — import the relative path through `deps/`:

```js
// assets/js/app.js
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { PhoenixExRatatuiHook } from "../../deps/phoenix_ex_ratatui/lib/assets/phoenix_ex_ratatui/main.js"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { PhoenixExRatatuiHook }
})

liveSocket.connect()
```

That's the only client-side wiring. The hook auto-discovers each
TUI's container by `phx-hook="PhoenixExRatatuiHook"` and handles cell
measurement, paint, keypress forwarding, and resize observation
itself.

## Step 1 — Write an `ExRatatui.App`

The `ExRatatui.App` you drive doesn't know it's running in a browser.
Same module that runs in a real terminal works unchanged here — the
package's transport just routes cells to the DOM instead of ANSI to
the tty.

```elixir
defmodule MyApp.Counter do
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  def mount(_opts), do: {:ok, %{n: 0}}

  def render(state, frame) do
    [
      {%Paragraph{
         text: "Count: #{state.n}\n\n+ increment   - decrement   q quit",
         block: %Block{title: " counter ", borders: [:all]}
       },
       %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
    ]
  end

  def handle_event(%Key{code: "+"}, s), do: {:noreply, %{s | n: s.n + 1}}
  def handle_event(%Key{code: "-"}, s), do: {:noreply, %{s | n: s.n - 1}}
  def handle_event(%Key{code: "q"}, s), do: {:stop, s}
  def handle_event(_, s), do: {:noreply, s}
end
```

## Step 2 — Pick an integration API

### Option A — `tui_live` router macro (zero boilerplate)

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use Phoenix.Router
  import PhoenixExRatatui.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    tui_live "/counter", MyApp.Counter
  end
end
```

That's the entire integration. Visit `/counter` and the Counter App
runs in the browser. The macro generates a wrapping LiveView at
compile time and registers it as a normal `live` route — invisible
to your app code, no module to write.

### Option B — `use PhoenixExRatatui.LiveView` (explicit form)

When you need to override `mount/3` to thread `current_user` from
the session, add custom assigns, or otherwise customise the LV
beyond what the router-level shortcut supports, write the wrapper
yourself:

```elixir
defmodule MyAppWeb.CounterLive do
  use PhoenixExRatatui.LiveView, app: MyApp.Counter

  # Override mount to layer your own logic on top.
  @impl true
  def mount(params, session, socket) do
    {:ok, socket} = super(params, session, socket)
    {:ok, assign(socket, :current_user, session["user_id"])}
  end
end

# router:
live "/counter", MyAppWeb.CounterLive
```

The macro generates the same callbacks the router-level shortcut
produces, but they're all `defoverridable`, so you can wrap any of
them with your own behaviour and call `super(...)`.

### Option C — `LiveComponent` (embed in an existing LiveView)

When the page is a regular Phoenix dashboard with a TUI sidebar, dev
console, or modal — anything where the TUI lives alongside other
content the user already controls — drop in the LiveComponent:

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
        <.live_component
          module={PhoenixExRatatui.LiveComponent}
          id="admin-tui"
          app={MyApp.SystemMonitorTui}
        />
      </div>
    </div>
    """
  end
end

# router:
live "/admin", MyAppWeb.AdminLive
```

The TUI's diff stream routes through `Phoenix.LiveView.send_update/3`
into the component's `update/2` (LiveComponents have no `handle_info`
— they share the parent LV's process). Everything else is identical
to the full-page paths.

## Decision matrix

| Use | When |
|---|---|
| `tui_live "/path", MyApp` | The whole page IS the TUI and you want zero boilerplate |
| `use PhoenixExRatatui.LiveView, app: MyApp` | The whole page IS the TUI but you need custom mount logic, per-route assigns, or `defoverridable` callbacks |
| `<.live_component module={PhoenixExRatatui.LiveComponent} ...>` | The page contains the TUI alongside other content (admin panels, dashboards, modals, dev tooling) |

All three are fully production-ready. The decision is purely about
fit with your project layout.

## Telemetry

Every integration emits the same `:telemetry` events. Attach the
default logger in dev:

```elixir
# in MyApp.Application.start/2
PhoenixExRatatui.Telemetry.attach_default_logger(level: :info)
```

Or wire `Telemetry.Metrics` for production dashboards:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      summary("phoenix_ex_ratatui.transport.connect.stop.duration",
        unit: {:native, :millisecond}
      ),
      counter("phoenix_ex_ratatui.transport.disconnect"),
      summary("phoenix_ex_ratatui.render.frame.stop.duration",
        unit: {:native, :microsecond}
      ),
      counter("phoenix_ex_ratatui.input.forward")
    ]
  end
end
```

See `PhoenixExRatatui.Telemetry`'s moduledoc for the full event
catalogue.

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
  [`PhoenixExRatatui.Router`](`PhoenixExRatatui.Router`), and
  [`PhoenixExRatatui.Transport`](`PhoenixExRatatui.Transport`)
- Read the [`examples/demo/`](https://github.com/mcass19/phoenix_ex_ratatui/tree/main/examples/demo)
  README and source for a working minimal Phoenix app that uses
  both `tui_live` and `LiveComponent` against the same TUI
- For the upstream cell-extraction primitive, see
  [`ExRatatui.CellSession`](https://hexdocs.pm/ex_ratatui/ExRatatui.CellSession.html)

# Telemetry

`phoenix_ex_ratatui` emits [`:telemetry`](https://hexdocs.pm/telemetry/) events at the boundaries the LiveView integration itself controls. They sit one layer above the events `ex_ratatui` already emits — together they give a complete profile of a browser-driven TUI without double-counting any single operation.

## Event tree at a glance

```
[:phoenix_ex_ratatui, :transport, :connect]    span    — mount + Transport boot (first full frame)
[:phoenix_ex_ratatui, :transport, :disconnect] single  — Transport.stop/2 teardown
[:phoenix_ex_ratatui, :render, :frame]         span    — diff encoded to JSON + push_event
[:phoenix_ex_ratatui, :input, :forward]        single  — decoded client input → runtime
[:phoenix_ex_ratatui, :intent, :dispatch]      single  — runtime intent → push_navigate and friends
```

Span events emit `:start` / `:stop` / `:exception` suffixes. Most handlers only attach to `:stop` for timing and `:exception` for failures.

See `PhoenixExRatatui.Telemetry` for the full metadata reference.

## Quick start: log every event

```elixir
# in MyApp.Application.start/2, or an IEx session:
PhoenixExRatatui.Telemetry.attach_default_logger(level: :info)
```

Detach with `PhoenixExRatatui.Telemetry.detach_default_logger/0`.

## Wiring `Telemetry.Metrics`

If `Telemetry.Metrics` is already running (e.g. behind a LiveDashboard), add these alongside whatever `ex_ratatui` metrics matter:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Time-to-first-frame on mount.
      summary("phoenix_ex_ratatui.transport.connect.stop.duration",
        unit: {:native, :millisecond}
      ),

      # How many sessions opened / closed.
      counter("phoenix_ex_ratatui.transport.disconnect"),

      # Per-frame encode + push cost (typically microseconds).
      summary("phoenix_ex_ratatui.render.frame.stop.duration",
        unit: {:native, :microsecond}
      ),

      # Client inputs flowing browser → server.
      counter("phoenix_ex_ratatui.input.forward"),

      # Navigation intents dispatched into the socket.
      counter("phoenix_ex_ratatui.intent.dispatch")
    ]
  end
end
```

## Pairing with `ex_ratatui`'s events

The two trees are complementary, not duplicative:

| Concern | Owned by |
| ------- | -------- |
| `mount/1` runtime, App `handle_event/2`, render command building | `[:ex_ratatui, ...]` |
| Mount + Transport boot, diff-to-JSON encode + `push_event/3` over the socket, client input forwarding, intent dispatch | `[:phoenix_ex_ratatui, ...]` |

Attach to whichever is needed. A typical setup attaches `[:ex_ratatui, :runtime, :event, :stop]` for App-level latency and `[:phoenix_ex_ratatui, :render, :frame, :stop]` for the wire cost — together they show where time is going without instrumenting either layer manually.

## Custom handlers

The public helpers `PhoenixExRatatui.Telemetry.span/3` and `PhoenixExRatatui.Telemetry.execute/3` are thin wrappers around `:telemetry.span/3` and `:telemetry.execute/3` that prepend `:phoenix_ex_ratatui` to the event name. Use them when building a higher-level wrapper around the macros and emitting events under the same namespace.

For one-off handlers, attach directly:

```elixir
:telemetry.attach(
  "my-app-frame-tracker",
  [:phoenix_ex_ratatui, :render, :frame, :stop],
  &MyApp.TuiTracker.handle_frame/4,
  nil
)
```

Always use a captured module function (`&MyApp.TuiTracker.handle_frame/4`), not an anonymous function — `:telemetry` logs a performance warning otherwise.

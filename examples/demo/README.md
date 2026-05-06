# Demo — `phoenix_ex_ratatui`

A minimal Phoenix app exercising both integration paths against the
same `ExRatatui.App`:

  * **`/counter`** — full-page TUI mounted via `tui_live` (one line
    in the router; no wrapper module).
  * **`/admin`** — embedded TUI inside a regular LiveView via
    `PhoenixExRatatui.LiveComponent`. Same Counter App, alongside
    a Phoenix-native heading and footer.

Both pages drive `Demo.Counter`, an `ExRatatui.App` that paints a
counter and increments it on `+`/`-` keypresses.

## Prerequisites

  * Elixir 1.17+ / Erlang 26+
  * Node.js 22+
  * Sibling checkouts of `phoenix_ex_ratatui` and `ex_ratatui` next
    to this `examples/demo/` directory:

    ```
    elixir/
    ├── ex_ratatui/
    ├── phoenix_ex_ratatui/
    │   └── examples/
    │       └── demo/         <- you are here
    ```

## Running

From inside `examples/demo/`:

```sh
mix deps.get
cd assets && npm install && cd ..
mix phx.server
```

Then open:

  * <http://localhost:4000/counter> — full-page TUI via `tui_live`
  * <http://localhost:4000/admin>   — TUI embedded as a LiveComponent

Use **+** / **-** to change the counter, **q** to quit (the TUI's
runtime exits cleanly; reload the page to mount fresh).

## What to look at

  * [`lib/demo/counter.ex`](lib/demo/counter.ex) — the `ExRatatui.App`. Note that nothing
    here is Phoenix-aware. The same module would run unchanged
    over SSH, in `kino_ex_ratatui`, or on a Nerves badge.
  * [`lib/demo_web/router.ex`](lib/demo_web/router.ex) — `tui_live "/counter", Demo.Counter`
    is the entire integration for the full-page route. The `/admin`
    route maps to a hand-written LiveView so you can see the
    LiveComponent in context.
  * [`lib/demo_web/live/admin_live.ex`](lib/demo_web/live/admin_live.ex) — the LiveView that
    embeds `PhoenixExRatatui.LiveComponent`. Renders surrounding
    content alongside the TUI.
  * [`assets/js/app.js`](assets/js/app.js) — the JS-hook wiring. One
    `import` of the bundle from `deps/phoenix_ex_ratatui/`, one
    entry in `LiveSocket`'s `hooks`, done.

## Telemetry

The application's `start/2` attaches the default logger so every
`phoenix_ex_ratatui` event prints to the console at `:info` level.
Open `iex -S mix phx.server` and use the page to see mount /
render / disconnect events fly by — useful for verifying the
integration end-to-end.

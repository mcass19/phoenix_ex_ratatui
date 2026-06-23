# Demo — `phoenix_ex_ratatui`

A Phoenix app showing the integration shapes against real `ExRatatui.App`s, all sharing one violet `ExRatatui.Theme` palette.

  * **`/`** ([`HomeLive`](lib/demo_web/live/home_live.ex)) — full-page TUI, reducer runtime. Matrix-style digital rain (`Canvas`) under an `EX RATATUI` `BigText` title.
  * **`/chat`** ([`ChatLive`](lib/demo_web/live/chat_live.ex)) — full-page TUI, callbacks runtime. A chat UI exercising most of the rich widget catalogue: `Markdown`, `Textarea`, `Throbber`, `Popup`, `WidgetList`, `SlashCommands`, `Scrollbar`.
  * **`/admin`** ([`AdminLive`](lib/demo_web/live/admin_live.ex)) — a plain `Phoenix.LiveView` embedding a reducer-runtime `LiveComponent` ([`SystemMonitorPanel`](lib/demo_web/live/system_monitor_panel.ex): `Gauge`, `Table`, `/proc` stats) alongside Phoenix-native page chrome.
  * **`/coexistence`** ([`CoexistenceLive`](lib/demo_web/live/coexistence_live.ex)) — a full-page TUI `LiveView` that *also* defines its own `handle_event/3` (a toolbar `phx-click`) and `handle_info/2` (a one-second page tick). The toolbar (plain HTML) and the TUI (cell diffs) update independently — the library consumes its own events/messages through lifecycle hooks, so your callbacks coexist with the TUI without clobbering it.

Navigation between pages flows through runtime intents (`{:navigate, "/path"}`), dispatched by the macros into `push_navigate/2` and friends.

## Prerequisites

  * Elixir 1.17+ / Erlang 26+, Node.js 22+
  * A sibling `phoenix_ex_ratatui` checkout next to `examples/demo/` (the `path` dep in `mix.exs`); `ex_ratatui` comes from Hex.

## Running

From `examples/demo/`:

```sh
mix deps.get
cd assets && npm install && cd ..
mix phx.server
```

Then open <http://localhost:4003>. Each view shows its key hints along the bottom.

## What to look at

  * [`lib/demo_web/router.ex`](lib/demo_web/router.ex) — the `live/3` routes, one per integration shape.
  * [`home_live.ex`](lib/demo_web/live/home_live.ex) and [`chat_live.ex`](lib/demo_web/live/chat_live.ex) — `use PhoenixExRatatui.LiveView`, on the reducer and callbacks runtimes respectively.
  * [`system_monitor_panel.ex`](lib/demo_web/live/system_monitor_panel.ex) — `use PhoenixExRatatui.LiveComponent`, embedded by [`admin_live.ex`](lib/demo_web/live/admin_live.ex).
  * [`coexistence_live.ex`](lib/demo_web/live/coexistence_live.ex) — a TUI `LiveView` defining its own `handle_event/3` + `handle_info/2` next to the `tui_*` callbacks; the cleanest read on how page callbacks and the TUI coexist.
  * [`lib/demo/`](lib/demo) — the Phoenix-agnostic pieces the views share: `MatrixRain` (pure rain model), `Theme` (the palette), `UI` (footer nav hints).
  * [`assets/js/app.js`](assets/js/app.js) — the whole JS wiring: one import of the hook, one entry in `LiveSocket`'s `hooks`.

## Telemetry

`Demo.Application.start/2` carries a commented-out `PhoenixExRatatui.Telemetry.attach_default_logger/1` call — uncomment it to print every mount / render / disconnect event to stdout.

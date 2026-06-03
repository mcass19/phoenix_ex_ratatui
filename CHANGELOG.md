# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-06-03

### Fixed

- **Key modifiers now decode to strings, not atoms.** Input from the JS hook produces `%ExRatatui.Event.Key{modifiers: ["ctrl"]}` — the same `[String.t()]` shape the NIF-backed transports (SSH, terminal, kino) emit — instead of `[:ctrl]`. A TUI matching `%Key{modifiers: ["ctrl"]}` now behaves identically across all transports; previously a Ctrl binding written the upstream way silently failed to match under phoenix.
- Ship the `guides/` directory in the Hex package (`mix.exs` `files`) so the Getting Started guide renders on hexdocs.
- Correct the README examples table: the Home demo runs on the reducer runtime, not callbacks.
- Fix the documented JS bundle size (~5KB, not ~4KB) and the `Transport.start_link/1` return-shape doc (it includes `:mod`).

### Changed

- Move the README demo GIF from `assets/` to `.github/demo.gif`, leaving `assets/` for the JS build pipeline only.
- Promote telemetry to a standalone [Telemetry guide](guides/telemetry.md), extracted from Getting Started and surfaced in the README Guides table — matching `ex_ratatui` and `kino_ex_ratatui`.
- Add an Ecosystem section to the README linking `ex_ratatui` and `kino_ex_ratatui`.
- Add `:telemetry` to `extra_applications`, matching `ex_ratatui` and `kino_ex_ratatui`.
- Drop the `skip_code_autolink_to` docs config: link the `handle_info/2`/`terminate/2` callback mentions with the `c:` prefix and render the hidden upstream ExRatatui.Server as plain text.

### Examples

- The `examples/demo` app now pulls `ex_ratatui` from Hex transitively through the `phoenix_ex_ratatui` path dependency, dropping the sibling `ex_ratatui` path override and the `rustler` build fallback now that ex_ratatui 0.10 is released.

## [0.1.0] - 2026-06-01

### Added

- **First release.** `phoenix_ex_ratatui` runs an `ExRatatui.App` inside a [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view), painting the rendered cell buffer directly into the DOM as `<span>` cells over the LiveView socket. No xterm.js, no ANSI on the wire — just structured cell deltas.

- **Reducer runtime support.** Both macros accept `runtime: :reducer` to generate a reducer-style proxy (`use ExRatatui.App, runtime: :reducer`). User-facing callbacks shift from `tui_mount/1` + `tui_handle_event/2` + `tui_handle_info/2` to `tui_init/1` + `tui_update/2` (with `{:event, _}` / `{:info, _}` wrapped messages) + `tui_subscriptions/1`. The default remains `:callbacks`. Concrete demo: `examples/demo/lib/demo_web/live/system_monitor_panel.ex` ports `ex_ratatui`'s `system_monitor.exs` example, dropping the `Process.send_after` ticking pattern in favor of a single `Subscription.interval/3` declared in `tui_subscriptions/1`.

- **Auto-focus on full-page TUIs.** The LV macro emits `data-phx-ex-ratatui-autofocus="true"` on its container; the JS hook reads it on mount and calls `focus({ preventScroll: true })`. Users no longer need to click the cell grid to start typing. Embedded `LiveComponent`s deliberately don't auto-focus — they're alongside other page content the user already interacts with.

- **Inter-page navigation via runtime intents.** A TUI can return `{:noreply, state, intents: [{:navigate, "/path"}]}` (or `:patch`, `:redirect`, including `[external: url]`) from any handler. Intents flow through ExRatatui.Server's `intent_writer_fn` into the LV, where the macro's `handle_info/2` dispatches via `Phoenix.LiveView.push_navigate/2` (and siblings). Unrecognised intents are dropped at warning level — TUIs stay forward-compatible. Public helper `PhoenixExRatatui.LiveView.dispatch_intent/2` handles the four standard shapes; consumers can layer their own dispatch table on top. Intents from `{:stop, state, intents: ...}` transitions fire before the server exits, so a "logout" key that returns `{:stop, state, intents: [{:redirect, "/login"}]}` works as expected. For embedded LiveComponents, intents bubble up to the parent LV via `send/2` (Phoenix forbids redirects from inside `LiveComponent.update/2`); the parent must forward `{:phoenix_ex_ratatui, :intent, intent}` messages to `dispatch_intent/2`. New `[:phoenix_ex_ratatui, :intent, :dispatch]` telemetry event fires once per intent.

- **Two unified-module integration APIs**, both backed by the same `PhoenixExRatatui.Transport`. The same module is both the Phoenix LV/LC and the `ExRatatui.App` driving it — a hidden `Module.Runtime` proxy generated via `@after_compile` conforms to `ExRatatui.App` by delegating to `tui_*` callbacks on your module. This sidesteps the `handle_info/2` arity collision between Phoenix LV (msg, socket) and `ExRatatui.App` (msg, state).
  - **`use PhoenixExRatatui.LiveView`** — full-page TUI route. Mounted via Phoenix's regular `live/3`. Defines six overridable callbacks: `tui_mount/1`, `tui_render/2`, `tui_handle_event/2`, `tui_handle_info/2`, `tui_terminate/2`, `tui_mount_opts/1`. Phoenix LV callbacks (`mount/3`, `render/1`, `handle_event/3`, `handle_info/2`) are also `defoverridable` for users who need to thread `current_user`, custom assigns, or per-route logic.
  - **`use PhoenixExRatatui.LiveComponent`** — embeddable variant hosting a TUI inside an existing LiveView alongside other content. Same `tui_*` callback shape as the LV macro, with diffs routed via `Phoenix.LiveView.send_update/3` (since LiveComponents share the parent LV's process and have no `handle_info/2`).

- **`PhoenixExRatatui.Transport`** — connection-level helper implementing the `ExRatatui.Transport` behaviour. `start_link/1` constructs an `ExRatatui.CellSession` at the given dimensions, builds a writer that ships rendered diffs to a target pid (or via a custom writer override for the LiveComponent's `send_update` path), and starts an ExRatatui.Server linked to the caller. Public surface: `start_link/1`, `push_event/2`, `resize/3`, `stop/2`. Server lifecycle is managed by the link — when the LiveView exits, the linked Server's `terminate/2` runs deterministically, closing the CellSession and emitting transport-disconnect telemetry.

- **`PhoenixExRatatui.Renderer.Html`** — wire-encoder converting `%CellSession.Diff{}` into a JSON-friendly `%{"width", "height", "ops"}` payload suitable for `Phoenix.LiveView.push_event/3`. Each op is a 7-element array `[row, col, sym, fg, bg, mods, skip]` — arrays not objects to halve the wire size on full payloads (a 200×60 diff goes from ~1MB to ~360KB before gzip). Color/modifier encoding documented in the module: named atoms become strings, `{:rgb, r, g, b}` becomes `["rgb", r, g, b]`, `{:indexed, n}` becomes `["indexed", n]`. The headline guarantee is `Jason.encode!/decode!` round-trip — pinned by a property test.

- **`PhoenixExRatatui.Telemetry`** — `:telemetry` integration mirroring the shape of `ExRatatui.Telemetry` one layer up. Events fire at the boundaries this package controls (mount + Transport boot, frame push, input forward, Transport teardown) without overlapping the `:runtime`/`:session`/`:transport` events `ex_ratatui` already emits. Two spans (`[:phoenix_ex_ratatui, :transport, :connect]` with `:mod`/`:width`/`:height`/`:target`; `[:phoenix_ex_ratatui, :render, :frame]` with `:mod`/`:width`/`:height`/`:ops_count`), two single events (`[:phoenix_ex_ratatui, :transport, :disconnect]` with `:mod`/`:reason`; `[:phoenix_ex_ratatui, :input, :forward]` with `:mod`/`:event`). Public helpers: `span/3`, `execute/3`, `attach_default_logger/1`, `detach_default_logger/0`. Documented in the moduledoc with a `Telemetry.Metrics` example for LiveDashboard wiring.

- **JS hook bundle** at `lib/assets/phoenix_ex_ratatui/main.js` — pure ES2020, no third-party deps (4.1KB minified vs. kino's ~250KB xterm.js bundle). Cell-grid painter that measures char box on mount, pushes initial `phx_ex_ratatui:resize`, listens for `phx_ex_ratatui:render` events to paint cells by direct `cells[row][col]` lookup, forwards `keydown` as `phx_ex_ratatui:input` with browser-key → ExRatatui-code mapping (`ArrowUp` → `"up"`, F-keys preserved, modifiers tracked), and re-pushes `:resize` on container resize via `ResizeObserver`. 16-color Tango palette + computed 256-color cube + RGB passthrough. Auto-applied container defaults (monospace font, `white-space: pre`, `line-height: 1`, `tabIndex: 0`) only fire if the user hasn't already supplied a value. Bundled output committed so installing from hex needs no Node toolchain; CI's "Verify JS bundle is in sync" step runs `npm ci && npm run build` and asserts `git diff --exit-code lib/assets/`.

- **Server-side dependency on `ex_ratatui`'s `:cell_session` transport tag** — the upstream half of the integration ships in `ex_ratatui 0.10`, via ExRatatui.Server's `{:cell_session, %CellSession{}, cell_writer_fn}` shape. This package depends on it through `{:ex_ratatui, "~> 0.10"}`.

- **Test coverage at 100%** across every covered module (Transport, Renderer.Html, LiveView, LiveComponent, Telemetry, the main module). Test fixtures and `Phoenix.LiveComponent`-based modules (which have a known `:cover` line-1 quirk caused by macro-injected helpers) are excluded from the threshold check via documented `mix.exs` ignore_modules entries. 94 tests + 7 doctests + 5 properties + LiveViewTest integration coverage with `live_isolated/3` + `render_hook/3` + `assert_push_event/3` against a minimum `Phoenix.Endpoint` test fixture.

- **Three-job CI matrix** mirroring [`kino_ex_ratatui`](https://github.com/mcass19/kino_ex_ratatui)'s shape: Elixir 1.17/Erlang 26.2.5.16, Elixir 1.18/Erlang 27.3.4.6, Elixir 1.19/Erlang 28.2 (lint job). Lint job runs `mix format --check-formatted`, `mix deps.unlock --check-unused`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix xref graph --format cycles --fail-above 0`, `mix dialyzer --format github`, JS bundle sync verification, and `mix test --cover`. Non-lint jobs run `mix test`.

- **[Getting Started guide](guides/getting_started.md)** walking through both unified-module APIs, the JS hook wiring, and the typical project structure. **[Examples directory](https://github.com/mcass19/phoenix_ex_ratatui/tree/main/examples/demo)** ships a minimal Phoenix app under `examples/demo/` that demonstrates the unified LV and LC side-by-side — useful as a copy-paste starting point for new integrations.

[Unreleased]: https://github.com/mcass19/phoenix_ex_ratatui/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/mcass19/phoenix_ex_ratatui/compare/v0.1.0...0.1.1
[0.1.0]: https://github.com/mcass19/phoenix_ex_ratatui/releases/tag/v0.1.0

# PhoenixExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_ex_ratatui.svg)](https://hex.pm/packages/phoenix_ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/phoenix_ex_ratatui)
[![CI](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/phoenix_ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/phoenix_ex_ratatui.svg)](https://github.com/mcass19/phoenix_ex_ratatui/blob/main/LICENSE)

Run [ExRatatui](https://github.com/mcass19/ex_ratatui) apps inside a [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view).

`PhoenixExRatatui` is the LiveView counterpart to [`kino_ex_ratatui`](https://github.com/mcass19/kino_ex_ratatui): a thin transport that pipes the runtime's rendered **cell buffer** to the browser, where a small JS hook paints cells directly into the DOM as `<span>` elements. No terminal emulator, no ANSI on the wire — just structured cell deltas over the LiveView socket. Phones get real touch events.

## Status

**Pre-release** — public API is being built up chunk by chunk. The first hex release will follow once the [`CellSession`](https://hexdocs.pm/ex_ratatui/cell_session.html) primitive ships in an `ex_ratatui` release. Until then, see [CONTRIBUTING.md](CONTRIBUTING.md) for local-dev setup against a sibling checkout.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

PhoenixExRatatui is built on [ExRatatui](https://github.com/mcass19/ex_ratatui), a general-purpose terminal UI library for Elixir. If you're interested in improving the underlying rendering, widgets, or layout engine, contributions to ExRatatui are very welcome as well.

## License

MIT — see [LICENSE](LICENSE).

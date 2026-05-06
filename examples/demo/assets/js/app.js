// Demo app.js — shows the minimum wiring needed to bring the
// PhoenixExRatatui hook into a Phoenix LiveView project.
//
// `phoenix_ex_ratatui` resolves as a normal npm module because
// `assets/package.json` lists it under `dependencies` with a
// `file:` source pointing at the Elixir package root. The package
// ships a top-level `package.json` whose `main` field points at
// the bundled hook — same pattern Phoenix's own JS deps
// (`phoenix`, `phoenix_live_view`) use.
//
// In a project depending on phoenix_ex_ratatui via hex, the
// `file:` source in package.json becomes
// `file:../deps/phoenix_ex_ratatui` and nothing else changes.

import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { PhoenixExRatatuiHook },
});

liveSocket.connect();

window.liveSocket = liveSocket;

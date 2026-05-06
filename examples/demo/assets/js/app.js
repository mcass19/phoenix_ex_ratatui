// Demo app.js — shows the minimum wiring needed to bring the
// PhoenixExRatatui hook into a Phoenix LiveView project.
//
// The bundle path is `deps/phoenix_ex_ratatui/lib/assets/...` because
// our Mix dep is a path checkout sitting two levels up. For a real
// project depending on the package via Hex, replace the import path
// with `phoenix_ex_ratatui/lib/assets/phoenix_ex_ratatui/main.js`
// or vendor the file into your own assets/ tree.

import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui/lib/assets/phoenix_ex_ratatui/main.js";

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

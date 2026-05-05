// esbuild bundle script for the phoenix_ex_ratatui LiveView hook.
//
// Inputs:
//   js/main.js  — entrypoint exporting the Hook object
//
// Outputs:
//   ../lib/assets/phoenix_ex_ratatui/main.js
//
// Run via `npm run build` (minified) or `npm run build:dev` (sourcemaps).
//
// Unlike kino_ex_ratatui this bundle has no third-party deps — we paint
// cells directly into the DOM, no terminal emulator. The bundle is
// pure ES2020 with the Hook surface LiveView calls into.
import * as esbuild from "esbuild";

const dev = process.argv.includes("--dev");

await esbuild.build({
  entryPoints: ["js/main.js"],
  outdir: "../lib/assets/phoenix_ex_ratatui",
  bundle: true,
  format: "esm",
  target: ["es2020"],
  minify: !dev,
  sourcemap: dev,
  logLevel: "info",
});

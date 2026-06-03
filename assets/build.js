// esbuild bundle script for the phoenix_ex_ratatui LiveView hook.
//
// Inputs:
//   js/main.js  — entrypoint exporting the Hook object
//
// Outputs:
//   ../lib/assets/phoenix_ex_ratatui/main.js
//
// Run via `npm run build` (minified) or `npm run build:dev` (sourcemaps).
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

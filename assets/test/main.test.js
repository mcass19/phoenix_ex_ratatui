// Unit tests for the pure functions behind the LiveView hook.
//
// Uses Node's built-in test runner (`node --test`) — no third-party
// deps, matching the bundle's dependency-free ethos. The hook's DOM
// methods (paint, measure, ResizeObserver) aren't exercised here; this
// pins the wire-decoding and style logic that has no browser
// dependency and is the easiest to get subtly wrong.

import { test } from "node:test";
import assert from "node:assert/strict";

import { __test__ } from "../js/main.js";

const { colorToCss, indexedColor, buildStyle, keyToCode, modifiersFor, NAMED_COLORS } =
  __test__;

test("colorToCss resolves the color shapes ExRatatui sends", () => {
  assert.equal(colorToCss(null), null);
  assert.equal(colorToCss("reset"), null);
  assert.equal(colorToCss("red"), "#cc0000");
  assert.equal(colorToCss("not_a_color"), null);
  assert.equal(colorToCss(["rgb", 200, 100, 50]), "rgb(200, 100, 50)");
  assert.equal(colorToCss(["indexed", 1]), "#cc0000");
});

test("indexedColor covers the named 16, the 6x6x6 cube, and the grayscale ramp", () => {
  // First 16 map to the named Tango palette.
  assert.equal(indexedColor(0), NAMED_COLORS.black);
  assert.equal(indexedColor(1), NAMED_COLORS.red);
  assert.equal(indexedColor(15), NAMED_COLORS.white);

  // 16..231 form the color cube; channel 0 -> 0, otherwise 55 + v*40.
  assert.equal(indexedColor(16), "rgb(0, 0, 0)");
  assert.equal(indexedColor(196), "rgb(255, 0, 0)");

  // 232..255 are a 24-step grayscale ramp at (n-232)*10 + 8.
  assert.equal(indexedColor(232), "rgb(8, 8, 8)");
  assert.equal(indexedColor(255), "rgb(238, 238, 238)");
});

test("buildStyle emits dynamic-only declarations and resolved fg/bg", () => {
  assert.deepEqual(buildStyle(null, null, []), { fg: "", bg: "", css: "" });

  assert.deepEqual(buildStyle("red", "blue", []), {
    fg: "#cc0000",
    bg: "#3465a4",
    css: "color:#cc0000;background-color:#3465a4",
  });

  assert.equal(buildStyle("red", null, ["bold"]).css, "color:#cc0000;font-weight:bold");
  assert.equal(buildStyle(null, null, ["italic"]).css, "font-style:italic");
  assert.equal(buildStyle(null, null, ["dim"]).css, "opacity:0.6");
});

test("buildStyle combines underline and strikethrough into one declaration", () => {
  assert.equal(buildStyle(null, null, ["underlined"]).css, "text-decoration:underline");
  assert.equal(buildStyle(null, null, ["crossed_out"]).css, "text-decoration:line-through");
  assert.equal(
    buildStyle(null, null, ["underlined", "crossed_out"]).css,
    "text-decoration:underline line-through",
  );
});

test("buildStyle renders `reversed` as an fg/bg swap, not a color invert", () => {
  // Both sides concrete: straight swap.
  const swapped = buildStyle("red", "blue", ["reversed"]);
  assert.equal(swapped.fg, "#3465a4");
  assert.equal(swapped.bg, "#cc0000");

  // One side unset: fall back to the default for the missing side.
  const oneSide = buildStyle("red", null, ["reversed"]);
  assert.equal(oneSide.fg, "#000000"); // DEFAULT_BG fills the empty bg
  assert.equal(oneSide.bg, "#cc0000"); // fg moves to bg

  // Neither side set: white-on-black default, the xterm-y baseline.
  const neither = buildStyle(null, null, ["reversed"]);
  assert.equal(neither.fg, "#000000");
  assert.equal(neither.bg, "#eeeeec");
});

test("keyToCode maps named keys, lowercases F-keys, and passes printables through", () => {
  assert.equal(keyToCode({ key: "ArrowUp" }), "up");
  assert.equal(keyToCode({ key: "Enter" }), "enter");
  assert.equal(keyToCode({ key: "Escape" }), "esc");
  assert.equal(keyToCode({ key: "F5" }), "f5");
  assert.equal(keyToCode({ key: "a" }), "a");
});

test("modifiersFor collects the active modifier keys in canonical order", () => {
  assert.deepEqual(modifiersFor({}), []);
  assert.deepEqual(modifiersFor({ ctrlKey: true, shiftKey: true }), ["ctrl", "shift"]);
  assert.deepEqual(modifiersFor({ ctrlKey: true, shiftKey: true, altKey: true, metaKey: true }), [
    "ctrl",
    "shift",
    "alt",
    "meta",
  ]);
});

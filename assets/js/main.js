// Phoenix LiveView Hook for `PhoenixExRatatui.LiveView` and
// `PhoenixExRatatui.LiveComponent`.
//
// Lifecycle:
//   1. mounted()   — measure cell dimensions, push initial resize
//   2. handleEvent("phx_ex_ratatui:render", payload) — paint diff ops
//                    onto the cell grid
//   3. ResizeObserver fires on viewport changes — re-measure and push
//   4. keydown listener forwards keys as input events
//   5. destroyed() — clean up listeners

// ----------------------------------------------------------------------
// Color tables
// ----------------------------------------------------------------------

const NAMED_COLORS = {
  black: "#000000",
  red: "#cc0000",
  green: "#4e9a06",
  yellow: "#c4a000",
  blue: "#3465a4",
  magenta: "#75507b",
  cyan: "#06989a",
  gray: "#d3d7cf",
  dark_gray: "#555753",
  light_red: "#ef2929",
  light_green: "#8ae234",
  light_yellow: "#fce94f",
  light_blue: "#729fcf",
  light_magenta: "#ad7fa8",
  light_cyan: "#34e2e2",
  white: "#eeeeec",
};

// `reversed` falls back to these when the cell has no concrete fg/bg
// to swap. Picking white-on-black matches the xterm-y default that
// most ratatui themes assume.
const DEFAULT_FG = NAMED_COLORS.white;
const DEFAULT_BG = NAMED_COLORS.black;

function colorToCss(color) {
  if (color == null || color === "reset") return null;
  if (typeof color === "string") return NAMED_COLORS[color] ?? null;
  if (Array.isArray(color)) {
    if (color[0] === "rgb") return `rgb(${color[1]}, ${color[2]}, ${color[3]})`;
    if (color[0] === "indexed") return indexedColor(color[1]);
  }
  return null;
}

function indexedColor(n) {
  if (n < 16) {
    const order = [
      "black", "red", "green", "yellow", "blue", "magenta", "cyan", "gray",
      "dark_gray", "light_red", "light_green", "light_yellow",
      "light_blue", "light_magenta", "light_cyan", "white",
    ];
    return NAMED_COLORS[order[n]];
  }
  if (n < 232) {
    const i = n - 16;
    const r = Math.floor(i / 36);
    const g = Math.floor((i % 36) / 6);
    const b = i % 6;
    const step = (v) => (v === 0 ? 0 : 55 + v * 40);
    return `rgb(${step(r)}, ${step(g)}, ${step(b)})`;
  }
  const v = (n - 232) * 10 + 8;
  return `rgb(${v}, ${v}, ${v})`;
}

// ----------------------------------------------------------------------
// Per-cell base styling lives in a CSS class injected once into the
// document. Keeping `display`/`width`/`height`/`text-align` out of
// inline style means setCell() can do a single short cssText write
// for the dynamic bits (color, weight, ...) without re-parsing the
// base each frame. Dimensions ride on CSS variables set on the
// container so multiple hooks with different font sizes coexist.
// ----------------------------------------------------------------------

const STYLE_TAG_ID = "phx-ex-ratatui-cell-style";

function ensureBaseStyle() {
  if (document.getElementById(STYLE_TAG_ID)) return;
  const tag = document.createElement("style");
  tag.id = STYLE_TAG_ID;
  tag.textContent =
    ".pxr-row{display:flex;line-height:1}" +
    ".pxr-cell{display:inline-block;width:var(--pxr-cw);height:var(--pxr-ch);text-align:center}";
  document.head.appendChild(tag);
}

// ----------------------------------------------------------------------
// Style assembly
// ----------------------------------------------------------------------
//
// Walks the modifiers array exactly once and returns:
//   { fg, bg, mods, css }
// where `css` is the dynamic-only declaration string we'll assign to
// `cell.style.cssText`. fg/bg in the result are the *resolved* CSS
// strings ("" when none) — useful as memo fields because two source
// shapes that resolve identically (null vs "reset", indexed vs rgb
// for the same color) hit the memo correctly.
//
// `reversed` is implemented as an fg/bg swap (with a default-color
// fallback when one side is null) instead of `filter:invert(1)`.
// `filter` creates a per-cell stacking context in Firefox that's
// genuinely expensive at TUI grid sizes.
function buildStyle(fg, bg, modifiers) {
  let fgCss = colorToCss(fg) || "";
  let bgCss = colorToCss(bg) || "";

  let bold = false, italic = false, dim = false;
  let under = false, cross = false, reversed = false;
  // Single pass through modifiers — .includes() called 6 times means
  // 6 array scans; this is one.
  for (let i = 0; i < modifiers.length; i++) {
    const m = modifiers[i];
    if (m === "bold") bold = true;
    else if (m === "italic") italic = true;
    else if (m === "dim") dim = true;
    else if (m === "underlined") under = true;
    else if (m === "crossed_out") cross = true;
    else if (m === "reversed") reversed = true;
  }

  if (reversed) {
    const newFg = bgCss || DEFAULT_BG;
    const newBg = fgCss || DEFAULT_FG;
    fgCss = newFg;
    bgCss = newBg;
  }

  // Build the cssText incrementally. Concatenation with a mutable
  // string is faster than push+join for short strings on V8/SpiderMonkey.
  let css = "";
  if (fgCss) css = "color:" + fgCss;
  if (bgCss) css += (css ? ";" : "") + "background-color:" + bgCss;
  if (bold) css += (css ? ";" : "") + "font-weight:bold";
  if (italic) css += (css ? ";" : "") + "font-style:italic";
  if (dim) css += (css ? ";" : "") + "opacity:0.6";
  if (under && cross) css += (css ? ";" : "") + "text-decoration:underline line-through";
  else if (under) css += (css ? ";" : "") + "text-decoration:underline";
  else if (cross) css += (css ? ";" : "") + "text-decoration:line-through";

  return { fg: fgCss, bg: bgCss, css };
}

// ----------------------------------------------------------------------
// Browser key → ExRatatui key code mapping
// ----------------------------------------------------------------------

const KEY_MAP = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
  Enter: "enter",
  Escape: "esc",
  Backspace: "backspace",
  Tab: "tab",
  Delete: "delete",
  Insert: "insert",
  Home: "home",
  End: "end",
  PageUp: "page_up",
  PageDown: "page_down",
};

function keyToCode(event) {
  if (KEY_MAP[event.key]) return KEY_MAP[event.key];
  if (/^F\d+$/.test(event.key)) return event.key.toLowerCase();
  return event.key;
}

function modifiersFor(event) {
  const mods = [];
  if (event.ctrlKey) mods.push("ctrl");
  if (event.shiftKey) mods.push("shift");
  if (event.altKey) mods.push("alt");
  if (event.metaKey) mods.push("meta");
  return mods;
}

// ----------------------------------------------------------------------
// The Hook
// ----------------------------------------------------------------------

export const PhoenixExRatatuiHook = {
  mounted() {
    this.cells = [];
    this.charWidth = 0;
    this.charHeight = 0;

    if (this.el.tabIndex < 0) this.el.tabIndex = 0;

    if (!this.el.style.fontFamily) {
      this.el.style.fontFamily = "ui-monospace, monospace";
    }
    if (!this.el.style.whiteSpace) this.el.style.whiteSpace = "pre";
    if (!this.el.style.lineHeight) this.el.style.lineHeight = "1";
    if (!this.el.style.overflow) this.el.style.overflow = "hidden";

    ensureBaseStyle();

    // Full-page LV TUIs auto-focus on mount so users don't have to
    // click the cell grid before keystrokes flow. The macro sets
    // `data-phx-ex-ratatui-autofocus="true"` on the container.
    // LiveComponents intentionally don't auto-focus — they're
    // embedded alongside other page content the user already
    // interacts with.
    if (this.el.dataset.phxExRatatuiAutofocus === "true") {
      this.el.focus({ preventScroll: true });
    }

    this.measureChar();
    this.reportSize();

    this.handleEvent("phx_ex_ratatui:render", (payload) => this.applyDiff(payload));

    this.resizeObserver = new ResizeObserver(() => this.reportSize());
    this.resizeObserver.observe(this.el);

    this.keydownListener = (event) => this.onKeydown(event);
    this.el.addEventListener("keydown", this.keydownListener);
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.keydownListener) this.el.removeEventListener("keydown", this.keydownListener);
  },

  measureChar() {
    const probe = document.createElement("span");
    probe.style.cssText = "visibility:hidden;position:absolute;font:inherit;white-space:pre";
    probe.textContent = "M";
    this.el.appendChild(probe);
    const rect = probe.getBoundingClientRect();
    this.charWidth = rect.width || 8;
    this.charHeight = rect.height || 16;
    probe.remove();

    // Publish geometry to the cell stylesheet via CSS vars.
    this.el.style.setProperty("--pxr-cw", this.charWidth + "px");
    this.el.style.setProperty("--pxr-ch", this.charHeight + "px");
  },

  reportSize() {
    if (!this.charWidth || !this.charHeight) return;
    const rect = this.el.getBoundingClientRect();
    let cols = Math.floor(rect.width / this.charWidth);
    let rows = Math.floor(rect.height / this.charHeight);

    // If the container has no concrete size yet (empty parent with
    // no explicit dimensions, or `display: none` ancestor while the
    // page is rendering), fall back to a conventional 80x24 default.
    // The painted cells will then drive the container's size, and a
    // subsequent ResizeObserver fire reports the real measurement
    // once the layout settles.
    if (cols < 1 || rows < 1) {
      cols = 80;
      rows = 24;
    }

    this.pushEventTo(this.el, "phx_ex_ratatui:resize", { cols, rows });
  },

  applyDiff({ width, height, ops }) {
    const dimsChanged =
      this.cells.length !== height ||
      (this.cells[0] && this.cells[0].length !== width);

    if (dimsChanged) this.buildGrid(width, height);

    for (let i = 0; i < ops.length; i++) {
      const [row, col, sym, fg, bg, mods, skip] = ops[i];
      this.setCell(row, col, sym, fg, bg, mods, skip);
    }
  },

  buildGrid(width, height) {
    this.el.replaceChildren();
    this.cells = [];

    for (let r = 0; r < height; r++) {
      const row = document.createElement("div");
      row.className = "pxr-row";
      const rowCells = new Array(width);

      for (let c = 0; c < width; c++) {
        const cell = document.createElement("span");
        cell.className = "pxr-cell";
        cell.textContent = " ";
        // Pre-seed memo fields so the first paint still memo-skips
        // empty-on-empty cells (server diffs after a resize often
        // emit unchanged blanks).
        cell._sym = " ";
        cell._fg = "";
        cell._bg = "";
        cell._mods = "";
        row.appendChild(cell);
        rowCells[c] = cell;
      }

      this.cells.push(rowCells);
      this.el.appendChild(row);
    }
  },

  setCell(row, col, sym, fg, bg, modifiers, skip) {
    const rowCells = this.cells[row];
    if (!rowCells) return;
    const cell = rowCells[col];
    if (!cell) return;
    if (skip) return;

    // Cheap modifiers key — a stable string, computed once. We use it
    // both for the memo compare and (implicitly) inside buildStyle's
    // single pass. modifiers is typically 0–3 entries so join is
    // basically free.
    const modsKey = modifiers.length ? modifiers.join(",") : "";
    const built = buildStyle(fg, bg, modifiers);

    // Memo: compare resolved fields, not raw inputs. This catches
    // semantic equality (null vs "reset", named vs indexed for the
    // same color) and avoids JSON.stringify on the hot path.
    if (
      cell._sym === sym &&
      cell._fg === built.fg &&
      cell._bg === built.bg &&
      cell._mods === modsKey
    ) {
      return;
    }

    cell._sym = sym;
    cell._fg = built.fg;
    cell._bg = built.bg;
    cell._mods = modsKey;

    if (cell.textContent !== sym) cell.textContent = sym;

    // Single short cssText write — no base style mixed in, so the
    // engine parses ~30–80 chars instead of ~150. When there's no
    // dynamic style at all, assigning "" is the cheapest form of
    // clear.
    cell.style.cssText = built.css;
  },

  onKeydown(event) {
    event.preventDefault();
    this.pushEventTo(this.el, "phx_ex_ratatui:input", {
      kind: "key",
      code: keyToCode(event),
      modifiers: modifiersFor(event),
      press_kind: "press",
    });
  },
};

export default PhoenixExRatatuiHook;

// Pure functions exposed for unit tests.
export const __test__ = {
  colorToCss,
  indexedColor,
  buildStyle,
  keyToCode,
  modifiersFor,
  NAMED_COLORS,
  DEFAULT_FG,
  DEFAULT_BG,
};

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
// Style assembly
// ----------------------------------------------------------------------

function styleFor(fg, bg, modifiers) {
  const parts = [];
  const fgCss = colorToCss(fg);
  const bgCss = colorToCss(bg);
  if (fgCss) parts.push(`color:${fgCss}`);
  if (bgCss) parts.push(`background-color:${bgCss}`);

  if (modifiers.includes("bold")) parts.push("font-weight:bold");
  if (modifiers.includes("italic")) parts.push("font-style:italic");
  if (modifiers.includes("dim")) parts.push("opacity:0.6");

  const decorations = [];
  if (modifiers.includes("underlined")) decorations.push("underline");
  if (modifiers.includes("crossed_out")) decorations.push("line-through");
  if (decorations.length) parts.push(`text-decoration:${decorations.join(" ")}`);

  if (modifiers.includes("reversed")) parts.push("filter:invert(1)");

  return parts.join(";");
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
      row.style.cssText = "display:flex;line-height:1";
      const rowCells = new Array(width);

      for (let c = 0; c < width; c++) {
        const cell = document.createElement("span");
        cell.style.cssText = `display:inline-block;width:${this.charWidth}px;height:${this.charHeight}px;text-align:center`;
        cell.textContent = " ";
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

    cell.textContent = sym;
    const baseStyle = `display:inline-block;width:${this.charWidth}px;height:${this.charHeight}px;text-align:center`;
    const extra = styleFor(fg, bg, modifiers);
    cell.style.cssText = extra ? `${baseStyle};${extra}` : baseStyle;
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
  styleFor,
  keyToCode,
  modifiersFor,
  NAMED_COLORS,
};

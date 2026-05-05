defmodule PhoenixExRatatui.Renderer.Html do
  @moduledoc """
  Encodes `ExRatatui.CellSession.Diff` payloads for transmission to the
  browser via `Phoenix.LiveView.push_event/3`.

  LiveView's `push_event/3` only accepts JSON-serializable terms — atoms
  encode as strings (via `Jason`), but tuples like `{:rgb, r, g, b}` do
  not encode cleanly. This module bridges the gap: convert each
  `%CellSession.Cell{}` into a fixed-shape array that the JS hook on
  the other side can read positionally without allocating an object
  per cell.

  ## Wire shape

  A diff payload becomes a map ready for `push_event/3`:

      %{
        "width" => 80,
        "height" => 24,
        "ops" => [
          [row, col, symbol, fg, bg, modifiers, skip],
          ...
        ]
      }

  Where each value follows these encodings:

    * `row`, `col` — integers, zero-indexed
    * `symbol` — UTF-8 string (single character or grapheme cluster)
    * `fg`, `bg` — color encoding:
        - `:reset` → `"reset"`
        - named atoms (`:red`, `:dark_gray`, ...) → matching string (`"red"`)
        - `{:rgb, r, g, b}` → `["rgb", r, g, b]`
        - `{:indexed, n}` → `["indexed", n]`
    * `modifiers` — list of strings in canonical bitflag order
      (`["bold", "italic"]`); empty list when no modifiers are set
    * `skip` — boolean; `true` means "leave whatever was here"

  ## Why arrays not objects per op

  A 200×60 full diff is 12_000 cells. Encoded as objects with named
  keys (`{"row": 0, "col": 0, "symbol": " ", "fg": "reset", ...}`) each
  cell is roughly 80 bytes; encoded as a 7-element array each cell is
  roughly 30 bytes. At websocket frame scale that's the difference
  between ~1MB and ~360KB on a single full-paint, before gzip. Since
  every browser implements `Array#0` access in a single CPU instruction,
  the JS side pays nothing for the positional read.

  ## Defaults are not omitted

  Every cell in the diff carries a full 7-element op even when most of
  its fields are at their default values (`"reset"`, `[]`, `false`).
  Omitting defaults would shrink the payload further but would push
  schema knowledge into the JS hook, and the diff path already filters
  cells aggressively — frames that "shouldn't" carry a cell at all
  don't appear in `:ops` to begin with. We can revisit if profiling
  flags it.
  """

  alias ExRatatui.CellSession.Cell
  alias ExRatatui.CellSession.Diff

  @typedoc """
  JSON-friendly encoded color: a string for named/reset colors, or a
  tagged 4- or 2-element array for RGB and indexed colors.
  """
  @type encoded_color ::
          String.t()
          | [String.t() | non_neg_integer(), ...]

  @typedoc """
  JSON-friendly encoded cell: a 7-element list in `[row, col, symbol,
  fg, bg, modifiers, skip]` order.
  """
  @type encoded_cell ::
          [
            non_neg_integer()
            | String.t()
            | encoded_color()
            | [String.t()]
            | boolean(),
            ...
          ]

  @typedoc """
  Full diff payload as it appears on the LiveView socket. String map
  keys (not atoms) so it round-trips cleanly through `Jason`.
  """
  @type encoded_diff :: %{
          required(String.t()) => non_neg_integer() | [encoded_cell()]
        }

  @doc """
  Encodes an `ExRatatui.CellSession.Diff` into the JSON-friendly map
  shape `Phoenix.LiveView.push_event/3` ships to the client.

  See the moduledoc for the full wire shape.

  ## Examples

      iex> alias ExRatatui.CellSession.{Cell, Diff}
      iex> diff = %Diff{
      ...>   width: 2, height: 1,
      ...>   ops: [%Cell{row: 0, col: 0, symbol: "X", fg: :red, bg: :reset, modifiers: [:bold], skip: false}]
      ...> }
      iex> PhoenixExRatatui.Renderer.Html.encode_diff(diff)
      %{
        "width" => 2,
        "height" => 1,
        "ops" => [[0, 0, "X", "red", "reset", ["bold"], false]]
      }
  """
  @spec encode_diff(Diff.t()) :: encoded_diff()
  def encode_diff(%Diff{width: w, height: h, ops: ops}) do
    %{
      "width" => w,
      "height" => h,
      "ops" => Enum.map(ops, &encode_cell/1)
    }
  end

  @doc """
  Encodes a single cell into the 7-element list shape. Exposed for
  callers that need finer-grained control (e.g. encoding cells from
  a `Snapshot` rather than a `Diff`, or building a diff op by hand).
  """
  @spec encode_cell(Cell.t()) :: encoded_cell()
  def encode_cell(%Cell{
        row: row,
        col: col,
        symbol: symbol,
        fg: fg,
        bg: bg,
        modifiers: modifiers,
        skip: skip
      }) do
    [row, col, symbol, encode_color(fg), encode_color(bg), encode_modifiers(modifiers), skip]
  end

  @doc """
  Encodes a single color value. Named atoms become strings, RGB and
  indexed colors become tagged arrays.

  ## Examples

      iex> PhoenixExRatatui.Renderer.Html.encode_color(:reset)
      "reset"

      iex> PhoenixExRatatui.Renderer.Html.encode_color(:light_cyan)
      "light_cyan"

      iex> PhoenixExRatatui.Renderer.Html.encode_color({:rgb, 200, 100, 50})
      ["rgb", 200, 100, 50]

      iex> PhoenixExRatatui.Renderer.Html.encode_color({:indexed, 42})
      ["indexed", 42]
  """
  @spec encode_color(ExRatatui.Style.color()) :: encoded_color()
  def encode_color(color) when is_atom(color), do: Atom.to_string(color)
  def encode_color({:rgb, r, g, b}), do: ["rgb", r, g, b]
  def encode_color({:indexed, n}), do: ["indexed", n]

  @doc """
  Encodes a modifier list. Each atom becomes its string name; the list
  preserves canonical bitflag order (set by `ExRatatui.CellSession`'s
  encoder).

  ## Examples

      iex> PhoenixExRatatui.Renderer.Html.encode_modifiers([])
      []

      iex> PhoenixExRatatui.Renderer.Html.encode_modifiers([:bold, :italic])
      ["bold", "italic"]
  """
  @spec encode_modifiers([ExRatatui.Style.modifier()]) :: [String.t()]
  def encode_modifiers(modifiers) when is_list(modifiers) do
    Enum.map(modifiers, &Atom.to_string/1)
  end
end

defmodule PhoenixExRatatui.Renderer.HtmlTest do
  use ExUnit.Case, async: true

  doctest PhoenixExRatatui.Renderer.Html

  alias ExRatatui.CellSession.{Cell, Diff}
  alias PhoenixExRatatui.Renderer.Html

  describe "encode_color/1" do
    test "every named color round-trips as the matching string" do
      for color <- [
            :black,
            :red,
            :green,
            :yellow,
            :blue,
            :magenta,
            :cyan,
            :gray,
            :dark_gray,
            :light_red,
            :light_green,
            :light_yellow,
            :light_blue,
            :light_magenta,
            :light_cyan,
            :white,
            :reset
          ] do
        assert Html.encode_color(color) == Atom.to_string(color)
      end
    end

    test "RGB encodes as a tagged 4-element array" do
      assert Html.encode_color({:rgb, 200, 100, 50}) == ["rgb", 200, 100, 50]
      assert Html.encode_color({:rgb, 0, 0, 0}) == ["rgb", 0, 0, 0]
      assert Html.encode_color({:rgb, 255, 255, 255}) == ["rgb", 255, 255, 255]
    end

    test "indexed encodes as a tagged 2-element array" do
      assert Html.encode_color({:indexed, 0}) == ["indexed", 0]
      assert Html.encode_color({:indexed, 42}) == ["indexed", 42]
      assert Html.encode_color({:indexed, 255}) == ["indexed", 255]
    end
  end

  describe "encode_modifiers/1" do
    test "empty list stays empty" do
      assert Html.encode_modifiers([]) == []
    end

    test "every modifier atom maps to its string name in order" do
      assert Html.encode_modifiers([:bold, :dim, :italic, :underlined, :crossed_out, :reversed]) ==
               ["bold", "dim", "italic", "underlined", "crossed_out", "reversed"]
    end

    test "preserves input order (canonical order is set upstream by CellSession)" do
      # The Renderer's job is encoding, not normalising. Caller-side
      # invariants about modifier ordering are guaranteed by
      # CellSession's encoder (covered in ex_ratatui's property tests),
      # so we just trust the input here.
      assert Html.encode_modifiers([:reversed, :bold]) == ["reversed", "bold"]
    end
  end

  describe "encode_cell/1" do
    test "produces a 7-element list in [row, col, symbol, fg, bg, mods, skip] order" do
      cell = %Cell{
        row: 3,
        col: 7,
        symbol: "X",
        fg: :light_cyan,
        bg: :reset,
        modifiers: [:bold],
        skip: false
      }

      assert Html.encode_cell(cell) == [3, 7, "X", "light_cyan", "reset", ["bold"], false]
    end

    test "default cells encode with all field defaults visible (no compaction)" do
      # Documented behaviour: every cell carries all 7 fields even when
      # most are at defaults. A future optimisation pass can compact
      # this, but for now the wire shape is fixed-width to keep the JS
      # hook trivial.
      assert Html.encode_cell(%Cell{}) == [0, 0, " ", "reset", "reset", [], false]
    end

    test "RGB and indexed colors flow through as tagged arrays" do
      cell = %Cell{
        row: 0,
        col: 0,
        symbol: "•",
        fg: {:rgb, 12, 34, 56},
        bg: {:indexed, 200},
        modifiers: [],
        skip: false
      }

      assert Html.encode_cell(cell) == [
               0,
               0,
               "•",
               ["rgb", 12, 34, 56],
               ["indexed", 200],
               [],
               false
             ]
    end

    test "skip flag and multi-codepoint symbol round-trip unchanged" do
      cell = %Cell{
        row: 1,
        col: 2,
        symbol: "中",
        fg: :red,
        bg: :reset,
        modifiers: [:underlined, :crossed_out],
        skip: true
      }

      assert Html.encode_cell(cell) ==
               [1, 2, "中", "red", "reset", ["underlined", "crossed_out"], true]
    end
  end

  describe "encode_diff/1" do
    test "wraps width, height, and encoded ops under string keys" do
      diff = %Diff{
        width: 80,
        height: 24,
        ops: [
          %Cell{row: 0, col: 0, symbol: "A", fg: :red, bg: :reset, modifiers: [], skip: false}
        ]
      }

      assert Html.encode_diff(diff) == %{
               "width" => 80,
               "height" => 24,
               "ops" => [[0, 0, "A", "red", "reset", [], false]]
             }
    end

    test "empty ops list (no-op frame) encodes cleanly" do
      diff = %Diff{width: 10, height: 5, ops: []}

      assert Html.encode_diff(diff) == %{
               "width" => 10,
               "height" => 5,
               "ops" => []
             }
    end

    test "encoded payload is JSON-serialisable round-trip" do
      # The whole point of the Renderer: the result must survive
      # Jason.encode!/decode! losslessly. If anything in the encoder
      # accidentally produces a tuple, an atom in a value position,
      # or any other non-JSON term, this is the test that catches it.
      diff = %Diff{
        width: 4,
        height: 2,
        ops: [
          %Cell{
            row: 0,
            col: 0,
            symbol: "X",
            fg: {:rgb, 100, 150, 200},
            bg: {:indexed, 42},
            modifiers: [:bold, :italic],
            skip: false
          },
          %Cell{
            row: 1,
            col: 3,
            symbol: " ",
            fg: :reset,
            bg: :light_cyan,
            modifiers: [],
            skip: true
          }
        ]
      }

      encoded = Html.encode_diff(diff)
      json = Jason.encode!(encoded)
      decoded = Jason.decode!(json)

      assert decoded == %{
               "width" => 4,
               "height" => 2,
               "ops" => [
                 [0, 0, "X", ["rgb", 100, 150, 200], ["indexed", 42], ["bold", "italic"], false],
                 [1, 3, " ", "reset", "light_cyan", [], true]
               ]
             }
    end
  end
end

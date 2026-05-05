defmodule PhoenixExRatatui.Property.RendererHtmlPropertyTest do
  @moduledoc """
  Property-based invariants for `PhoenixExRatatui.Renderer.Html`.

  The example-based tests in `renderer/html_test.exs` cover hand-picked
  shapes; these properties prove the structural guarantees across the
  full input space:

    * every `%Cell{}` produces a 7-element list
    * every `%Diff{}` produces a 3-key map under `"width"`/`"height"`/`"ops"`
    * the encoded payload **always** survives `Jason.encode!/decode!`
      losslessly (the whole reason the Renderer exists)
    * encoded modifiers are a list of strings whose order matches the
      input atom-list order (Renderer is encoding-only — canonical
      ordering is the upstream encoder's job)
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.CellSession.{Cell, Diff}
  alias PhoenixExRatatui.Renderer.Html

  @named_colors ~w(
    black red green yellow blue magenta cyan gray
    dark_gray light_red light_green light_yellow light_blue
    light_magenta light_cyan white reset
  )a

  @modifiers ~w(bold dim italic underlined crossed_out reversed)a

  # Generators -------------------------------------------------------------

  defp color_gen do
    one_of([
      member_of(@named_colors),
      gen all(r <- integer(0..255), g <- integer(0..255), b <- integer(0..255)) do
        {:rgb, r, g, b}
      end,
      gen all(i <- integer(0..255)) do
        {:indexed, i}
      end
    ])
  end

  defp cell_gen do
    gen all(
          row <- integer(0..199),
          col <- integer(0..199),
          symbol <- string(:printable, max_length: 4),
          fg <- color_gen(),
          bg <- color_gen(),
          modifiers <- list_of(member_of(@modifiers), max_length: 6),
          skip <- boolean()
        ) do
      %Cell{
        row: row,
        col: col,
        symbol: symbol,
        fg: fg,
        bg: bg,
        modifiers: Enum.uniq(modifiers),
        skip: skip
      }
    end
  end

  defp diff_gen do
    gen all(
          width <- integer(1..200),
          height <- integer(1..60),
          ops <- list_of(cell_gen(), max_length: 16)
        ) do
      %Diff{width: width, height: height, ops: ops}
    end
  end

  # Properties -------------------------------------------------------------

  property "encode_color always produces a JSON-serialisable term" do
    check all(color <- color_gen()) do
      encoded = Html.encode_color(color)
      # JSON-friendly = string OR a list of (string | integer).
      assert is_binary(encoded) or is_list(encoded)
      assert {:ok, _} = Jason.encode(encoded)
    end
  end

  property "encode_cell always produces a 7-element list" do
    check all(cell <- cell_gen()) do
      encoded = Html.encode_cell(cell)
      assert is_list(encoded)
      assert length(encoded) == 7

      [row, col, symbol, fg, bg, mods, skip] = encoded
      assert row == cell.row
      assert col == cell.col
      assert symbol == cell.symbol
      assert is_binary(fg) or is_list(fg)
      assert is_binary(bg) or is_list(bg)
      assert is_list(mods) and Enum.all?(mods, &is_binary/1)
      assert is_boolean(skip)
    end
  end

  property "encode_modifiers maps every atom to its string and preserves order" do
    check all(modifiers <- list_of(member_of(@modifiers), max_length: 12)) do
      encoded = Html.encode_modifiers(modifiers)
      assert encoded == Enum.map(modifiers, &Atom.to_string/1)
    end
  end

  property "encode_diff produces a map with string keys :width, :height, :ops" do
    check all(diff <- diff_gen()) do
      encoded = Html.encode_diff(diff)

      assert is_map(encoded)
      assert Map.keys(encoded) |> Enum.sort() == ["height", "ops", "width"]
      assert encoded["width"] == diff.width
      assert encoded["height"] == diff.height
      assert is_list(encoded["ops"])
      assert length(encoded["ops"]) == length(diff.ops)
      assert Enum.all?(encoded["ops"], &(is_list(&1) and length(&1) == 7))
    end
  end

  property "encode_diff payload survives Jason.encode!/decode! losslessly" do
    # The headline contract. If this property ever fails, something in
    # the encoder is producing a non-JSON term (atom in a value
    # position, a tuple, a NIF reference, anything Jason chokes on)
    # and push_event/3 would silently drop the frame at runtime.
    check all(diff <- diff_gen()) do
      encoded = Html.encode_diff(diff)
      json = Jason.encode!(encoded)
      decoded = Jason.decode!(json)
      assert decoded == encoded
    end
  end
end

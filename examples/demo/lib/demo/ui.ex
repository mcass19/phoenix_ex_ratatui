defmodule Demo.UI do
  @moduledoc """
  Tiny shared UI helpers for the demo TUIs — bottom navigation hints,
  centered panels — so each view can focus on its own content.

  Not part of the `phoenix_ex_ratatui` public surface; living here in
  the example app keeps it out of the library and makes the
  abstraction available across all three demo TUIs.
  """

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Splits a frame into `[content_area, footer_area]` where the footer
  is a fixed-height row pinned to the bottom — the canonical
  "navigation hints at the bottom" TUI layout.
  """
  @spec split_for_footer(Rect.t(), pos_integer()) :: [Rect.t()]
  def split_for_footer(area, footer_height \\ 1) do
    Layout.split(area, :vertical, [{:min, 0}, {:length, footer_height}])
  end

  @doc """
  Builds a bottom-anchored navigation hints widget. `hints` is a
  list of `{key, label}` tuples; the produced row reads
  ` <key1> label1   <key2> label2 …`.
  """
  @spec nav_hints([{String.t(), String.t()}]) :: Paragraph.t()
  def nav_hints(hints) when is_list(hints) do
    text = " " <> Enum.map_join(hints, "   ", fn {k, l} -> "<#{k}> #{l}" end)

    %Paragraph{
      text: text,
      style: %Style{fg: :dark_gray}
    }
  end

  @doc """
  Centers a fixed-size box inside `outer`, returning the centered
  `Rect`. If `outer` is smaller than `width x height`, the box clamps
  to whatever fits.
  """
  @spec center_box(Rect.t(), pos_integer(), pos_integer()) :: Rect.t()
  def center_box(%Rect{} = outer, width, height) do
    w = min(width, outer.width)
    h = min(height, outer.height)

    %Rect{
      x: outer.x + div(outer.width - w, 2),
      y: outer.y + div(outer.height - h, 2),
      width: w,
      height: h
    }
  end
end

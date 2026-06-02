defmodule Demo.ThemeTest do
  use ExUnit.Case, async: true

  alias Demo.Theme
  alias ExRatatui.Style

  test "palette/0 is the demo's violet theme" do
    palette = Theme.palette()
    assert palette.accent == :light_magenta
    assert palette.border == :magenta
    assert palette.border_focused == :light_magenta
  end

  test "border_style/1 uses the border slot, focused uses the brighter accent border" do
    assert Theme.border_style() == %Style{fg: :magenta}
    assert Theme.border_style(focused: true) == %Style{fg: :light_magenta}
  end

  test "selection_style/0 pops black on the accent" do
    assert Theme.selection_style() == %Style{fg: :black, bg: :light_magenta}
  end

  test "text_style/1 uses the text slot, dim uses text_dim" do
    assert Theme.text_style().fg == :white
    assert Theme.text_style(dim: true).fg == :dark_gray
  end
end

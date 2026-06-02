defmodule Demo.Theme do
  @moduledoc """
  The demo's shared violet palette, built on `ExRatatui.Theme`.

  Gives the three demo TUIs one consistent look and showcases the
  Theme API — `border_style/1`, `selection_style/0`, `text_style/1`
  all derive their `%Style{}` from a single `%ExRatatui.Theme{}`
  rather than colors scattered across views.
  """

  alias ExRatatui.Theme

  @palette %Theme{
    primary: :light_magenta,
    accent: :light_magenta,
    border: :magenta,
    border_focused: :light_magenta,
    # `surface` doubles as the selection foreground, so black gives a
    # readable pop against the light-magenta accent background.
    surface: :black,
    surface_alt: :black,
    text: :white,
    text_dim: :dark_gray,
    success: :green,
    warning: :yellow,
    danger: :red
  }

  @doc "The demo's `%ExRatatui.Theme{}` palette."
  @spec palette() :: Theme.t()
  def palette, do: @palette

  @doc "Border style; pass `focused: true` for the brighter accent border."
  @spec border_style(keyword()) :: ExRatatui.Style.t()
  def border_style(opts \\ []), do: Theme.border_style(@palette, opts)

  @doc "Selection-highlight style (black on the accent)."
  @spec selection_style() :: ExRatatui.Style.t()
  def selection_style, do: Theme.selection_style(@palette)

  @doc "Body-text style; pass `dim: true` for hints and secondary text."
  @spec text_style(keyword()) :: ExRatatui.Style.t()
  def text_style(opts \\ []), do: Theme.text_style(@palette, opts)
end

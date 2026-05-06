defmodule DemoWeb.HomeLive do
  @moduledoc """
  Landing-page TUI. Centered banner + nav hints at the bottom — the
  canonical TUI layout. `<c>` and `<a>` emit runtime intents that the
  LV macro dispatches into `push_navigate`.
  """
  use PhoenixExRatatui.LiveView

  alias Demo.UI
  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @banner_lines [
    "",
    "~$  whoami",
    "",
    "run ex_ratatui apps inside Phoenix LiveView",
    "",
    "",
    "[ c ] chat    [ a ] admin",
    ""
  ]

  def tui_mount(_opts), do: {:ok, %{}}

  def tui_render(_state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [content_area, footer_area] = UI.split_for_footer(area)

    background = %Paragraph{
      text: "",
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :magenta}
      }
    }

    banner_height = length(@banner_lines) + 2
    banner_width = min(content_area.width - 4, 70)
    banner_area = UI.center_box(content_area, banner_width, banner_height)
    banner = UI.banner("~/phoenix_ex_ratatui", @banner_lines)

    footer = UI.nav_hints([{"c", "chat"}, {"a", "admin"}, {"q", "exit"}])

    [
      {background, content_area},
      {banner, banner_area},
      {footer, footer_area}
    ]
  end

  def tui_handle_event(%Key{code: "c"}, state),
    do: {:noreply, state, intents: [{:navigate, "/chat"}]}

  def tui_handle_event(%Key{code: "a"}, state),
    do: {:noreply, state, intents: [{:navigate, "/admin"}]}

  def tui_handle_event(%Key{code: "q"}, state),
    do:
      {:noreply, state,
       intents: [{:redirect, [external: "https://github.com/mcass19/phoenix_ex_ratatui"]}]}

  def tui_handle_event(_event, state), do: {:noreply, state}
end

defmodule DemoWeb.LoginLive do
  @moduledoc """
  Tiny landing-page TUI that demonstrates inter-page navigation via
  runtime intents. `<enter>` returns
  `{:noreply, state, intents: [{:navigate, "/counter"}]}` from
  `tui_handle_event/2`; the LV macro picks the intent up in
  `handle_info/2` and dispatches `Phoenix.LiveView.push_navigate/2`.
  """
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  def tui_mount(_opts), do: {:ok, %{}}

  def tui_render(_state, frame) do
    text = """

       phoenix_ex_ratatui demo

       Press <enter> to navigate to the counter
       Press <a> to navigate to the admin dashboard
    """

    paragraph = %Paragraph{
      text: text,
      style: %Style{fg: :light_cyan, modifiers: [:bold]},
      block: %Block{
        title: " login ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :magenta}
      }
    }

    [{paragraph, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  def tui_handle_event(%Key{code: "enter"}, state),
    do: {:noreply, state, intents: [{:navigate, "/counter"}]}

  def tui_handle_event(%Key{code: "a"}, state),
    do: {:noreply, state, intents: [{:navigate, "/admin"}]}

  def tui_handle_event(_event, state), do: {:noreply, state}
end

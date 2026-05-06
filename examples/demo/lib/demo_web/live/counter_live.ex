defmodule DemoWeb.CounterLive do
  @moduledoc """
  Full-page TUI counter — unified module is both the `Phoenix.LiveView`
  and the `ExRatatui.App` driving it. Mounted directly via the
  router's regular `live/3` macro.
  """
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  def tui_mount(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    text = """

       Count: #{state.n}

       +    increment
       -    decrement
       q    back to /login
    """

    paragraph = %Paragraph{
      text: text,
      style: %Style{fg: :light_cyan, modifiers: [:bold]},
      block: %Block{
        title: " phoenix_ex_ratatui counter ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :magenta}
      }
    }

    [{paragraph, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  def tui_handle_event(%Key{code: "+"}, state), do: {:noreply, %{state | n: state.n + 1}}
  def tui_handle_event(%Key{code: "-"}, state), do: {:noreply, %{state | n: state.n - 1}}

  def tui_handle_event(%Key{code: "q"}, state),
    do: {:noreply, state, intents: [{:navigate, "/login"}]}

  def tui_handle_event(_event, state), do: {:noreply, state}
end

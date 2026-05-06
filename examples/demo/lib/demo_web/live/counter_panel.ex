defmodule DemoWeb.CounterPanel do
  @moduledoc """
  Embeddable TUI counter — unified module is both the
  `Phoenix.LiveComponent` and the `ExRatatui.App` driving it. Drop
  it inside any LiveView's render with `<.live_component
  module={DemoWeb.CounterPanel} id="..." />`.
  """
  use PhoenixExRatatui.LiveComponent

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
       b    back to /login
    """

    paragraph = %Paragraph{
      text: text,
      style: %Style{fg: :light_cyan, modifiers: [:bold]},
      block: %Block{
        title: " counter (embedded) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :magenta}
      }
    }

    [{paragraph, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  def tui_handle_event(%Key{code: "+"}, state), do: {:noreply, %{state | n: state.n + 1}}
  def tui_handle_event(%Key{code: "-"}, state), do: {:noreply, %{state | n: state.n - 1}}

  def tui_handle_event(%Key{code: "b"}, state),
    do: {:noreply, state, intents: [{:navigate, "/login"}]}

  def tui_handle_event(_event, state), do: {:noreply, state}
end

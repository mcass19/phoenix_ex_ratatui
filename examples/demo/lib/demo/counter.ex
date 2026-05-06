defmodule Demo.Counter do
  @moduledoc """
  Tiny `ExRatatui.App` shared between both demo routes.

  Same module runs unchanged whether it's mounted via `tui_live`
  (full-page route), `use PhoenixExRatatui.LiveView` (explicit
  full-page LV), or `PhoenixExRatatui.LiveComponent` (embedded).
  Nothing in here is Phoenix-aware.
  """
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def mount(_opts), do: {:ok, %{n: 0}}

  @impl true
  def render(state, frame) do
    text = """

       Count: #{state.n}

       +    increment
       -    decrement
       q    quit
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

  @impl true
  def handle_event(%Key{code: "+"}, state), do: {:noreply, %{state | n: state.n + 1}}
  def handle_event(%Key{code: "-"}, state), do: {:noreply, %{state | n: state.n - 1}}
  def handle_event(%Key{code: "q"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state}
end

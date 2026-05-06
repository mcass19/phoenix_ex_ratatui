defmodule PhoenixExRatatui.TestComponent do
  @moduledoc """
  Unified-module fixture used by `PhoenixExRatatui.LiveComponentTest`
  to exercise the `PhoenixExRatatui.LiveComponent` macro end-to-end.
  """
  use PhoenixExRatatui.LiveComponent

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  def tui_mount(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [{%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}]
  end

  def tui_handle_event(%Key{code: "q"}, state), do: {:stop, state}

  def tui_handle_event(%Key{code: "navigate"}, state),
    do: {:noreply, state, intents: [{:navigate, "/elsewhere"}]}

  def tui_handle_event(_event, state), do: {:noreply, %{state | n: state.n + 1}}
end

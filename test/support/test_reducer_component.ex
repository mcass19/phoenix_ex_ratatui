defmodule PhoenixExRatatui.TestReducerComponent do
  @moduledoc """
  Reducer-runtime LiveComponent fixture. Its App callback is `tui_update/2`
  taking `({:event | :info}, state)` — the same shape `system_monitor_panel`
  uses in the demo. It must not collide with the LiveComponent assigns hook
  `tui_component_update/2` `(assigns, socket)`; this fixture guards that.
  """
  use PhoenixExRatatui.LiveComponent, runtime: :reducer

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  def tui_init(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [{%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}]
  end

  def tui_update({:event, _event}, state), do: {:noreply, %{state | n: state.n + 1}}
  def tui_update({:info, _msg}, state), do: {:noreply, state}
end

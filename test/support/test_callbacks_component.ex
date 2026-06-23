defmodule PhoenixExRatatui.TestCallbacksComponent do
  @moduledoc """
  Fixture proving a LiveComponent's own socket-level hooks
  (`tui_update/2`, `tui_component_event/3`) fire and coexist with the
  TUI after the delegation refactor. Records that each hook ran in
  assigns the test reads via the parent LV's component registry.
  """
  use PhoenixExRatatui.LiveComponent

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  def tui_mount(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [{%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}]
  end

  def tui_handle_event(_event, state), do: {:noreply, %{state | n: state.n + 1}}

  # The component's own socket-level hooks, defined normally.
  def tui_update(assigns, socket) do
    {:ok,
     socket
     |> Phoenix.Component.assign(assigns)
     |> Phoenix.Component.assign(:tui_update_ran, true)}
  end

  def tui_component_event("user:click", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :component_event_ran, true)}
  end
end

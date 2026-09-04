defmodule PhoenixExRatatui.CubeLive do
  @moduledoc """
  `PhoenixExRatatui.LiveView` fixture whose TUI is a full-frame
  pixel-mode `Viewport3D` (see `PhoenixExRatatui.CubeApp`). Used to
  assert the end-to-end pixel-region path: resize with a cell size,
  PNG regions in the pushed payload, and the unchanged-frame omission.
  """
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias PhoenixExRatatui.CubeApp

  def tui_mount(_opts), do: {:ok, %{angle: 0.0}}

  def tui_render(state, frame) do
    [{CubeApp.viewport(state.angle), %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  def tui_handle_event(%Key{code: "noop"}, state), do: {:noreply, state}
  def tui_handle_event(_event, state), do: {:noreply, %{state | angle: state.angle + 0.5}}
end

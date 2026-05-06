defmodule PhoenixExRatatui.TestLive do
  @moduledoc """
  Unified-module fixture used by `PhoenixExRatatui.LiveViewTest` to
  exercise the `__using__` macro end-to-end.

  Same module is both the `Phoenix.LiveView` and (via the macro's
  `@after_compile`-generated `PhoenixExRatatui.TestLive.Runtime`
  proxy) the `ExRatatui.App` driving the TUI. Mirrors the shape a
  real user-side TUI module would take.

  Paints a counter that increments on every event so the cell-diff
  path has a stable single-cell change to assert against.
  """
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  def tui_mount(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [{%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}]
  end

  def tui_handle_event(%Key{code: "q"}, state), do: {:stop, state}
  def tui_handle_event(_event, state), do: {:noreply, %{state | n: state.n + 1}}
end

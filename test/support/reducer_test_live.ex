defmodule PhoenixExRatatui.ReducerTestLive do
  @moduledoc """
  Unified-module fixture exercising the reducer runtime style of
  `PhoenixExRatatui.LiveView`. Same module is both a `Phoenix.LiveView`
  and (via the macro's `@after_compile` proxy) the reducer-style
  `ExRatatui.App` driving it.

  Reducer runtime callbacks: `tui_init/1`, `tui_render/2`,
  `tui_update/2` (messages wrapped as `{:event, _}` / `{:info, _}`),
  `tui_subscriptions/1`. No `tui_mount` or `tui_handle_event` — those
  are the callbacks-runtime entrypoints.
  """
  use PhoenixExRatatui.LiveView, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  def tui_init(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [{%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}]
  end

  def tui_update({:event, %Key{code: "q"}}, state), do: {:stop, state}
  def tui_update({:event, _event}, state), do: {:noreply, %{state | n: state.n + 1}}
  def tui_update({:info, _msg}, state), do: {:noreply, state}
end

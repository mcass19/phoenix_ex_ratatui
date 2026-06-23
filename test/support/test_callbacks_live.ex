defmodule PhoenixExRatatui.TestCallbacksLive do
  @moduledoc """
  Fixture proving a user's own `handle_event/3` and `handle_info/2`
  coexist with the TUI after the lifecycle-hook refactor.

  Defines both callbacks the way a real app would — a `phx-click`-style
  event handler and a PubSub-style message handler — and records that
  they fired in assigns the test can read. The library's own browser
  events and render/intent/EXIT messages are consumed by the lifecycle
  hooks attached in `mount/3`, so these clauses never see them.
  """
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  def tui_mount(_opts), do: {:ok, %{n: 0}}

  def tui_render(state, frame) do
    [{%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}]
  end

  def tui_handle_event(_event, state), do: {:noreply, %{state | n: state.n + 1}}

  # The user's OWN LiveView callbacks, defined normally alongside the TUI.
  @impl Phoenix.LiveView
  def handle_event("user:click", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :user_clicked, true)}
  end

  @impl Phoenix.LiveView
  def handle_info({:user_msg, value}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :user_msg, value)}
  end
end

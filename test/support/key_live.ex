defmodule PhoenixExRatatui.KeyLive do
  @moduledoc """
  Fixture for the key-release tests: forwards every event its TUI
  receives to the test process named in the session, and asks for key
  releases when the session says so.
  """
  use PhoenixExRatatui.LiveView

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    {:ok, socket} = super(params, session, socket)

    {:ok,
     Phoenix.Component.assign(socket,
       test_pid: session["test_pid"],
       releases?: session["releases?"]
     )}
  end

  def tui_mount_opts(socket),
    do: [test_pid: socket.assigns.test_pid, keyboard_enhancement: socket.assigns.releases?]

  def tui_mount(opts), do: {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid)}}

  def tui_render(_state, frame) do
    [
      {%ExRatatui.Widgets.Paragraph{text: "keys"},
       %ExRatatui.Layout.Rect{x: 0, y: 0, width: frame.width, height: 1}}
    ]
  end

  def tui_handle_event(event, state) do
    send(state.test_pid, {:tui_event, event})
    {:noreply, state}
  end
end

defmodule PhoenixExRatatui.TestApp do
  @moduledoc """
  Tiny `ExRatatui.App` used by the Transport tests.

  Echoes lifecycle events back to the test process via `:test_pid` so
  assertions can pin exactly which callback fired and when. Also paints
  a counter that increments on every event, which gives the cell-diff
  path a stable single-cell change to assert against (without painting
  the counter, post-event diffs would be empty and we'd lose visibility
  into whether render actually fired).
  """
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def mount(opts) do
    test_pid = Keyword.get(opts, :test_pid)
    if test_pid, do: send(test_pid, {:mounted, opts})
    {:ok, %{test_pid: test_pid, n: 0}}
  end

  @impl true
  def render(state, frame) do
    [
      {%Paragraph{text: "n=#{state.n}"}, %Rect{x: 0, y: 0, width: frame.width, height: 1}}
    ]
  end

  @impl true
  def handle_event(%Key{code: "q"}, state) do
    if state.test_pid, do: send(state.test_pid, {:event, %Key{code: "q"}})
    {:stop, state}
  end

  def handle_event(event, state) do
    if state.test_pid, do: send(state.test_pid, {:event, event})
    {:noreply, %{state | n: state.n + 1}}
  end

  @impl true
  def terminate(reason, state) do
    if state.test_pid, do: send(state.test_pid, {:terminated, reason})
    :ok
  end
end

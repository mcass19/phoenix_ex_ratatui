defmodule PhoenixExRatatui.TestParentLive do
  @moduledoc """
  Parent LiveView used by `PhoenixExRatatui.LiveComponentTest` to
  exercise the embeddable LiveComponent.

  Renders a heading + the LiveComponent so we can assert that the
  TUI lives alongside non-TUI content correctly. The component
  module is configurable via the LV's session so we can swap in
  `FailingTestComponent` for the mount-failure tests without
  needing a separate fixture LV.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    component = Map.get(session, "component", PhoenixExRatatui.TestComponent)
    {:ok, assign(socket, component: component)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 id="parent-heading">Parent</h1>
    <.live_component module={@component} id="embedded-tui" />
    """
  end
end

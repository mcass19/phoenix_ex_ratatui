defmodule PhoenixExRatatui.TestParentLive do
  @moduledoc """
  Parent LiveView used by `PhoenixExRatatui.LiveComponentTest` to
  exercise the embeddable LiveComponent.

  Renders a heading + the LiveComponent so we can assert that the
  TUI lives alongside non-TUI content correctly. The `:app` is
  configurable via the LV's session so we can swap in
  `FailingMountApp` for the mount-failure tests without needing a
  separate fixture LV.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    app = Map.get(session, "app", PhoenixExRatatui.TestApp)
    {:ok, assign(socket, app: app)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 id="parent-heading">Parent</h1>
    <.live_component module={PhoenixExRatatui.LiveComponent} id="embedded-tui" app={@app} />
    """
  end
end

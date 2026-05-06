defmodule DemoWeb.AdminLive do
  @moduledoc """
  Demonstrates `PhoenixExRatatui.LiveComponent` embedded alongside
  regular Phoenix-native content. The TUI is just one of several
  pieces of UI on the page.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main style="font-family: system-ui, sans-serif; max-width: 80ch; margin: 2rem auto; padding: 0 1rem;">
      <h1>Admin Dashboard</h1>

      <p>
        The widget below is a unified-module
        <code>PhoenixExRatatui.LiveComponent</code> running inside this
        regular Phoenix-rendered page. Resize the window or focus the
        TUI and press <kbd>+</kbd> / <kbd>-</kbd> — frames flow over the
        LiveView socket as cell deltas.
      </p>

      <section style="margin: 2rem 0; padding: 1rem; border: 1px solid #ddd; border-radius: 6px;">
        <h2 style="margin-top: 0;">Live counter (TUI)</h2>
        <!-- The LiveComponent fills its parent (width: 100%; height: 100%).
             We give the wrapping div an explicit height so there's room
             to render. Without this, the hook would fall back to its
             default 80x24 cells and overflow the section. -->
        <div style="height: 22em;">
          <.live_component module={DemoWeb.CounterPanel} id="admin-counter" />
        </div>
      </section>

      <p>
        For the same TUI logic as a full-page route — no surrounding
        chrome, no container — see <a href="/counter">/counter</a>,
        which mounts <code>DemoWeb.CounterLive</code> directly via the
        router's regular <code>live/3</code> macro.
      </p>
    </main>
    """
  end
end

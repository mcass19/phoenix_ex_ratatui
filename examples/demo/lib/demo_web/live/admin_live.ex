defmodule DemoWeb.AdminLive do
  @moduledoc """
  Plain `Phoenix.LiveView` hosting the reducer-runtime
  `DemoWeb.SystemMonitorPanel` LiveComponent alongside regular
  Phoenix-native page chrome. The TUI is one of several pieces of
  UI on the page.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # Forwarding clause documented in `PhoenixExRatatui.LiveComponent`'s
  # moduledoc — required because the embedded TUI emits a navigation
  # intent on `b` and the parent here is a plain `Phoenix.LiveView`.
  @impl true
  def handle_info({:phoenix_ex_ratatui, :intent, intent}, socket) do
    {:noreply, PhoenixExRatatui.LiveView.dispatch_intent(socket, intent)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main style="font-family: system-ui, sans-serif; max-width: 90ch; margin: 2rem auto; padding: 0 1rem;">
      <h1>Admin Dashboard</h1>

      <p>
        The panel below is a <strong>reducer-runtime</strong>
        <code>PhoenixExRatatui.LiveComponent</code> embedded inside
        this regular Phoenix LiveView page. Click the TUI to focus it,
        then press <kbd>r</kbd> to refresh, <kbd>c</kbd> to jump to
        the <a href="/chat">chat</a>, or <kbd>b</kbd> to head back to
        <a href="/">home</a> — every navigation is a runtime intent.
      </p>

      <p style="color: #555;">
        The dashboard ticks every two seconds via
        <code>ExRatatui.Subscription.interval/3</code> declared in
        <code>tui_subscriptions/1</code> — no <code>Process.send_after</code>,
        no manual reschedule.
      </p>

      <section style="margin: 1.5rem 0; padding: 1rem; border: 1px solid #ddd; border-radius: 6px;">
        <h2 style="margin-top: 0;">System Monitor (TUI)</h2>
        <!-- The LiveComponent fills its parent (width: 100%; height: 100%).
             We give the wrapping div an explicit height so there's room
             for the dashboard. Without this, the hook would fall back to
             its default 80x24 cells and overflow the section. -->
        <div style="height: 32em; border-radius: 4px; overflow: hidden;">
          <.live_component module={DemoWeb.SystemMonitorPanel} id="admin-monitor" />
        </div>
      </section>

      <p>
        Source: <code>examples/demo/lib/demo_web/live/system_monitor_panel.ex</code>
        — a port of <code>ex_ratatui</code>'s
        <code>system_monitor.exs</code> example, restructured to use
        the reducer runtime.
      </p>
    </main>
    """
  end
end

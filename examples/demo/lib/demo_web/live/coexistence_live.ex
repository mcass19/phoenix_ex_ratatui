defmodule DemoWeb.CoexistenceLive do
  @moduledoc """
  Minimal demo of defining your **own** LiveView callbacks alongside a TUI.

  This page is a `PhoenixExRatatui.LiveView` whose `render/1` wraps the TUI
  container in a plain HTML toolbar. The toolbar's button is handled by the
  module's own `handle_event/3`, and a one-second clock by its own
  `handle_info/2` — both coexist with the TUI's `tui_*` callbacks, which is
  exactly what used to silently break before the lifecycle-hook fix.

  Watch two things update independently on the same page:

    * the **toolbar** (plain HTML, driven by the LiveView's own
      `handle_event/3` + `handle_info/2`), and
    * the **TUI** (cell diffs, driven by `tui_handle_event/2`).

  No `super` gymnastics, no special wiring — define the callbacks normally.
  """
  use PhoenixExRatatui.LiveView

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  # ----- Our own LiveView callbacks (coexist with the TUI) -----

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    {:ok, socket} = super(params, session, socket)

    if connected?(socket), do: Process.send_after(self(), :page_tick, 1_000)

    {:ok, assign(socket, pings: 0, ticks: 0)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div style="display:flex;flex-direction:column;height:100vh;background:#0f0c14;color:#e9e4f5;font-family:ui-monospace,SFMono-Regular,Menlo,monospace">
      <div style="display:flex;gap:1rem;align-items:center;padding:.5rem .85rem;border-bottom:1px solid #2a2433;font-size:.85rem">
        <strong style="color:#ad7fa8">your own callbacks + a TUI</strong>
        <button
          type="button"
          phx-click="ping"
          style="background:#2a2433;color:#e9e4f5;border:1px solid #75507b;border-radius:4px;padding:.2rem .6rem;cursor:pointer"
        >
          ping (phx-click → handle_event)
        </button>
        <span style="opacity:.6">pings: {@pings}</span>
        <span style="opacity:.6">page ticks (handle_info): {@ticks}</span>
        <span style="margin-left:auto;display:flex;gap:.75rem">
          <.link navigate="/" style="color:#ad7fa8">home</.link>
          <.link navigate="/chat" style="color:#ad7fa8">chat</.link>
          <.link navigate="/admin" style="color:#ad7fa8">admin</.link>
        </span>
      </div>

      <div style="flex:1;min-height:0">
        <div
          id={@tui_container_id}
          phx-hook="PhoenixExRatatuiHook"
          phx-update="ignore"
          data-phx-ex-ratatui-runtime={inspect(@tui_runtime_mod)}
          data-phx-ex-ratatui-autofocus="true"
          style="width:100%;height:100%"
        >
        </div>
      </div>

      <p :if={@tui_error} style="padding:.5rem .85rem;color:#ef2929">TUI error: {@tui_error}</p>
    </div>
    """
  end

  # A plain phx-click — the library's lifecycle hook passes it through to
  # this clause.
  @impl Phoenix.LiveView
  def handle_event("ping", _params, socket) do
    {:noreply, assign(socket, :pings, socket.assigns.pings + 1)}
  end

  # A page-level message, unrelated to the TUI's render messages.
  @impl Phoenix.LiveView
  def handle_info(:page_tick, socket) do
    Process.send_after(self(), :page_tick, 1_000)
    {:noreply, assign(socket, :ticks, socket.assigns.ticks + 1)}
  end

  # ----- TUI callbacks -----

  def tui_mount(_opts), do: {:ok, %{keys: 0, last: "—"}}

  def tui_render(state, frame) do
    text = """

      This box is the TUI. The toolbar above is plain HTML.

      Keys pressed in here: #{state.keys}
      Last key: #{state.last}

      Click the TUI and type to drive it. Click "ping" for the
      page's own handle_event; the page-ticks counter is the
      page's own handle_info. Both run alongside this TUI.
    """

    [
      {%Paragraph{
         text: text,
         style: %Style{fg: :light_green},
         block: %Block{
           title: " TUI — tui_handle_event/2 ",
           borders: [:all],
           border_type: :rounded
         }
       }, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
    ]
  end

  def tui_handle_event(%Key{code: code}, state) do
    {:noreply, %{state | keys: state.keys + 1, last: code}}
  end

  def tui_handle_event(_event, state), do: {:noreply, state}
end

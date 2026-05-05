defmodule PhoenixExRatatui.LiveComponent do
  @moduledoc """
  Embeddable cell-grid TUI for `Phoenix.LiveView`.

  Where `PhoenixExRatatui.LiveView` (and its `tui_live` shortcut)
  give you a full-page TUI mounted directly from the router, this
  LiveComponent drops a TUI inside an existing LiveView alongside
  whatever else that LV is rendering — admin dashboards, dev
  consoles, half-page overlays.

  ## Quick start

      defmodule MyAppWeb.AdminLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <h1>Admin Dashboard</h1>
          <.live_component
            module={PhoenixExRatatui.LiveComponent}
            id="admin-tui"
            app={MyApp.AdminTui}
          />
          <p>Other admin content</p>
          \"\"\"
        end
      end

  ## Required assigns

    * `:id` — DOM id for the hook container. The LiveComponent's
      identity is `(module, id)`, so this is also how `send_update`
      finds the right component instance to update.
    * `:app` — module implementing `ExRatatui.App` to drive.

  ## Wire model

  LiveComponents share the parent LV's process — they don't have
  their own mailbox or `handle_info/2`. We solve that by handing
  the runtime Server a writer that calls
  `Phoenix.LiveView.send_update/3` instead of `send/2`. Each
  rendered diff arrives in `update(%{tui_diff: diff}, socket)` and
  flows out to the client via `push_event/3`.

  Mount-failure handling matches the LiveView macro: if `mod.mount/1`
  returns `{:error, _}`, the runtime server's init returns
  `{:stop, reason}`, the linked parent LV gets the EXIT, and we set
  `:tui_error` so the next render shows a fallback. **The parent LV
  must trap exits** for this to work — otherwise the EXIT signal
  kills the whole LV and the browser sees a reconnect. We set
  `Process.flag(:trap_exit, true)` lazily on the first resize event
  before calling `Transport.start_link/1`. This sets it on the
  parent LV process; if you embed multiple TUI components or your
  LV traps exits for other reasons, the flag is shared.

  ## When to reach for this vs. the LiveView macro

  Use `PhoenixExRatatui.LiveView` (or `PhoenixExRatatui.Router.tui_live`
  once that ships) when the page IS a TUI — the route's whole job
  is to render and drive an `ExRatatui.App`.

  Use this LiveComponent when the page contains a TUI alongside
  other content the user already controls — admin panels with a
  TUI sidebar, dashboards with a TUI dev console, embedded
  monitoring widgets, etc.

  ## Telemetry

  Same events as the LiveView macro:

    * `[:phoenix_ex_ratatui, :transport, :connect]` — span around
      `Transport.start_link/1` on the first resize
    * `[:phoenix_ex_ratatui, :render, :frame]` — span around each
      `encode_diff/1 + push_event/3` cycle
    * `[:phoenix_ex_ratatui, :input, :forward]` — event when client
      input is decoded and forwarded to the runtime
    * `[:phoenix_ex_ratatui, :transport, :disconnect]` — event when
      the LiveComponent's parent LV exits and the linked Server
      tears down

  See `PhoenixExRatatui.Telemetry` for the full event catalogue.
  """

  use Phoenix.LiveComponent

  alias PhoenixExRatatui.LiveView, as: PXRLV
  alias PhoenixExRatatui.Renderer.Html
  alias PhoenixExRatatui.Telemetry
  alias PhoenixExRatatui.Transport

  @impl true
  def mount(socket) do
    {:ok, assign(socket, tui: nil, tui_error: nil)}
  end

  @impl true
  # `tui_diff` is sent by the writer (built in `start_transport/3`)
  # via `Phoenix.LiveView.send_update/3` whenever the runtime
  # produces a frame. We encode and push immediately, then return
  # the socket WITHOUT merging :tui_diff into the assigns — it's a
  # one-shot value, not state.
  def update(%{tui_diff: diff}, socket) do
    meta = %{
      mod: socket.assigns.tui.mod,
      width: diff.width,
      height: diff.height,
      ops_count: length(diff.ops)
    }

    socket =
      Telemetry.span([:render, :frame], meta, fn ->
        push_event(socket, "phx_ex_ratatui:render", Html.encode_diff(diff))
      end)

    {:ok, socket}
  end

  # Fallthrough for the parent's normal render-side assigns (`:id`,
  # `:app`, plus whatever the user passes in). Merges them into the
  # component's socket so they're available to `render/1` and the
  # event handlers.
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div
        id={@id}
        phx-hook="PhoenixExRatatuiHook"
        phx-update="ignore"
        phx-target={@myself}
        data-phx-ex-ratatui-app={inspect(@app)}
      >
      </div>
      <%= if @tui_error do %>
        <p class="phoenix-ex-ratatui-error">TUI error: {@tui_error}</p>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("phx_ex_ratatui:resize", %{"cols" => cols, "rows" => rows}, socket)
      when is_integer(cols) and cols > 0 and is_integer(rows) and rows > 0 do
    socket =
      case socket.assigns.tui do
        nil -> start_transport(socket, cols, rows)
        refs -> resize_transport(socket, refs, cols, rows)
      end

    {:noreply, socket}
  end

  def handle_event("phx_ex_ratatui:input", payload, socket) when is_map(payload) do
    socket =
      case socket.assigns.tui do
        nil ->
          # Hook fired input before the resize. Drop silently — same
          # contract as the LiveView macro.
          socket

        refs ->
          event = PXRLV.decode_input(payload)
          Telemetry.execute([:input, :forward], %{}, %{mod: refs.mod, event: event})
          :ok = Transport.push_event(refs, event)
          socket
      end

    {:noreply, socket}
  end

  defp start_transport(socket, cols, rows) do
    parent_pid = self()
    component_module = __MODULE__
    component_id = socket.assigns.id

    # The parent LV has to trap exits so a Server crash (mount
    # failure, runtime error) returns cleanly via Transport's
    # error path instead of killing the whole LV. See the moduledoc
    # for the rationale and side effects.
    Process.flag(:trap_exit, true)

    writer = fn diff ->
      Phoenix.LiveView.send_update(parent_pid, component_module,
        id: component_id,
        tui_diff: diff
      )

      :ok
    end

    case Transport.start_link(
           mod: socket.assigns.app,
           width: cols,
           height: rows,
           target: parent_pid,
           writer: writer
         ) do
      {:ok, refs} ->
        assign(socket, :tui, refs)

      {:error, reason} ->
        assign(socket, :tui_error, inspect(reason))
    end
  end

  defp resize_transport(socket, refs, cols, rows) do
    case Transport.resize(refs, cols, rows) do
      :ok -> socket
      {:error, _} -> assign(socket, :tui_error, "session closed")
    end
  end
end

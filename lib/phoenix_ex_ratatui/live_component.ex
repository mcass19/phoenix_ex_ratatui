defmodule PhoenixExRatatui.LiveComponent do
  @moduledoc """
  Macro that turns the calling module into a `Phoenix.LiveComponent`
  hosting an embedded TUI — the same module is both the component and
  the `ExRatatui.App` it drives.

  Where `PhoenixExRatatui.LiveView` makes the page itself a TUI, this
  macro lets you drop a TUI inside an existing LiveView alongside
  whatever else that LV is rendering — admin dashboards, dev consoles,
  half-page overlays.

  ## Quick start

      defmodule MyAppWeb.AdminCounterPanel do
        use PhoenixExRatatui.LiveComponent

        def tui_mount(_opts), do: {:ok, %{count: 0}}
        def tui_render(state, frame), do: [...]
        def tui_handle_event(_event, state), do: {:noreply, state}
      end

      # In a parent LiveView:
      defmodule MyAppWeb.AdminLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <h1>Admin Dashboard</h1>
          <.live_component module={MyAppWeb.AdminCounterPanel} id="admin-counter" />
          <p>Other admin content</p>
          \"\"\"
        end
      end

  ## How it works

  Same trick as `PhoenixExRatatui.LiveView`: the macro injects
  `Phoenix.LiveComponent` callbacks AND, via `@after_compile`,
  generates a sibling `Module.Runtime` proxy that conforms to
  `ExRatatui.App` by delegating to your `tui_*` callbacks. The
  `handle_info/2` arity collision between LV and ExRatatui.App is
  the same in LiveComponents (well, LCs don't have handle_info, but
  the abstraction stays consistent).

  ## TUI callbacks

  Same as `PhoenixExRatatui.LiveView`:

    * `tui_mount/1`, `tui_render/2`, `tui_handle_event/2`,
      `tui_handle_info/2`, `tui_terminate/2`, `tui_mount_opts/1`

  See `PhoenixExRatatui.LiveView`'s moduledoc for full callback
  semantics.

  ## Threading parent assigns into the App

  The component's `update/2` receives assigns from the parent LV.
  Override `tui_mount_opts/1` (which gets the component socket) to
  thread them into `tui_mount/1`:

      def update(assigns, socket) do
        {:ok, assign(socket, assigns)}
      end

      def tui_mount_opts(socket), do: [user: socket.assigns.user]

      def tui_mount(opts), do: {:ok, %{user: opts[:user]}}

  ## Wire model

  LiveComponents share the parent LV's process — they don't have
  their own mailbox or `handle_info/2`. We hand the runtime Server a
  writer that calls `Phoenix.LiveView.send_update/3` instead of
  `send/2`. Each rendered diff arrives in `update(%{tui_diff: diff},
  socket)` and flows out to the client via `push_event/3`.

  Mount-failure handling matches the LiveView macro: if `tui_mount/1`
  returns `{:error, _}`, the runtime server's init returns
  `{:stop, reason}`, the linked parent LV gets the EXIT, and we set
  `:tui_error` so the next render shows a fallback. **The parent LV
  must trap exits** for this to work — otherwise the EXIT signal
  kills the whole LV. We set `Process.flag(:trap_exit, true)` lazily
  on the first resize event before calling `Transport.start_link/1`.
  This sets it on the parent LV process; if your LV traps exits for
  other reasons, the flag is shared.

  ## Telemetry

  Same events as `PhoenixExRatatui.LiveView` — see
  `PhoenixExRatatui.Telemetry`.
  """

  alias PhoenixExRatatui.LiveView, as: PXRLV

  @doc """
  Generates the unified LiveComponent + App module. See the moduledoc.
  """
  defmacro __using__(opts) do
    __build_using_quote__(opts)
  end

  @doc false
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def __build_using_quote__(_opts) do
    quote location: :keep do
      use Phoenix.LiveComponent

      @phoenix_ex_ratatui_runtime_mod Module.concat(__MODULE__, "Runtime")

      # ----- TUI callback defaults (all overridable) -----

      @doc false
      def tui_mount(_opts), do: {:ok, %{}}

      @doc false
      def tui_render(_state, _frame), do: []

      @doc false
      def tui_handle_event(_event, state), do: {:noreply, state}

      @doc false
      def tui_handle_info(_msg, state), do: {:noreply, state}

      @doc false
      def tui_terminate(_reason, _state), do: :ok

      @doc false
      def tui_mount_opts(_socket), do: []

      defoverridable tui_mount: 1,
                     tui_render: 2,
                     tui_handle_event: 2,
                     tui_handle_info: 2,
                     tui_terminate: 2,
                     tui_mount_opts: 1

      # ----- Phoenix.LiveComponent callbacks -----

      @impl Phoenix.LiveComponent
      def mount(socket) do
        {:ok,
         socket
         |> Phoenix.Component.assign(:tui, nil)
         |> Phoenix.Component.assign(:tui_error, nil)
         |> Phoenix.Component.assign(:tui_runtime_mod, @phoenix_ex_ratatui_runtime_mod)}
      end

      @impl Phoenix.LiveComponent
      # `tui_diff` is sent by the writer (built in `__start_transport__/3`)
      # via `Phoenix.LiveView.send_update/3` whenever the runtime
      # produces a frame. We encode and push immediately, then return
      # the socket WITHOUT merging :tui_diff into assigns — it's a
      # one-shot value, not state.
      def update(%{tui_diff: diff}, socket) do
        {:ok, PhoenixExRatatui.LiveComponent.__push_render__(socket, diff)}
      end

      def update(assigns, socket) do
        {:ok, Phoenix.Component.assign(socket, assigns)}
      end

      @impl Phoenix.LiveComponent
      def render(var!(assigns)) do
        ~H"""
        <div style="width:100%;height:100%">
          <div
            id={@id}
            phx-hook="PhoenixExRatatuiHook"
            phx-update="ignore"
            phx-target={@myself}
            data-phx-ex-ratatui-runtime={inspect(@tui_runtime_mod)}
            style="width:100%;height:100%"
          >
          </div>
          <%= if @tui_error do %>
            <p class="phoenix-ex-ratatui-error">TUI error: {@tui_error}</p>
          <% end %>
        </div>
        """
      end

      @impl Phoenix.LiveComponent
      def handle_event(
            "phx_ex_ratatui:resize",
            %{"cols" => cols, "rows" => rows},
            socket
          )
          when is_integer(cols) and cols > 0 and is_integer(rows) and rows > 0 do
        {:noreply,
         PhoenixExRatatui.LiveComponent.__handle_resize__(socket, __MODULE__, cols, rows)}
      end

      def handle_event("phx_ex_ratatui:input", payload, socket) when is_map(payload) do
        {:noreply, PhoenixExRatatui.LiveComponent.__handle_input__(socket, payload)}
      end

      defoverridable mount: 1, update: 2, render: 1, handle_event: 3

      @after_compile {PhoenixExRatatui.LiveView, :__define_runtime__}
    end
  end

  @doc false
  def __push_render__(socket, diff) do
    meta = %{
      mod: socket.assigns.tui.mod,
      width: diff.width,
      height: diff.height,
      ops_count: length(diff.ops)
    }

    PhoenixExRatatui.Telemetry.span([:render, :frame], meta, fn ->
      Phoenix.LiveView.push_event(
        socket,
        "phx_ex_ratatui:render",
        PhoenixExRatatui.Renderer.Html.encode_diff(diff)
      )
    end)
  end

  @doc false
  def __handle_resize__(socket, user_mod, cols, rows) do
    case socket.assigns.tui do
      nil -> __start_transport__(socket, user_mod, cols, rows)
      refs -> __resize_transport__(socket, refs, cols, rows)
    end
  end

  defp __start_transport__(socket, user_mod, cols, rows) do
    parent_pid = self()
    component_module = user_mod
    component_id = socket.assigns.id
    runtime_mod = Module.concat(user_mod, "Runtime")
    mount_opts = user_mod.tui_mount_opts(socket)

    # Parent LV must trap exits so a Server crash returns cleanly via
    # Transport's error path instead of killing the whole LV. See the
    # moduledoc for the rationale and side effects.
    Process.flag(:trap_exit, true)

    writer = fn diff ->
      Phoenix.LiveView.send_update(parent_pid, component_module,
        id: component_id,
        tui_diff: diff
      )

      :ok
    end

    start_link_opts =
      [
        mod: runtime_mod,
        width: cols,
        height: rows,
        target: parent_pid,
        writer: writer
      ] ++ mount_opts

    case PhoenixExRatatui.Transport.start_link(start_link_opts) do
      {:ok, refs} ->
        Phoenix.Component.assign(socket, :tui, refs)

      {:error, reason} ->
        Phoenix.Component.assign(socket, :tui_error, inspect(reason))
    end
  end

  defp __resize_transport__(socket, refs, cols, rows) do
    case PhoenixExRatatui.Transport.resize(refs, cols, rows) do
      :ok -> socket
      {:error, _} -> Phoenix.Component.assign(socket, :tui_error, "session closed")
    end
  end

  @doc false
  def __handle_input__(socket, payload) do
    case socket.assigns.tui do
      nil ->
        socket

      refs ->
        event = PXRLV.decode_input(payload)

        PhoenixExRatatui.Telemetry.execute([:input, :forward], %{}, %{mod: refs.mod, event: event})

        :ok = PhoenixExRatatui.Transport.push_event(refs, event)
        socket
    end
  end
end

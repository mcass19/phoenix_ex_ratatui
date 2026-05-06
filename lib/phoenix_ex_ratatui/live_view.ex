defmodule PhoenixExRatatui.LiveView do
  @moduledoc """
  Macro that generates a full-page `Phoenix.LiveView` wrapping an
  `ExRatatui.App`.

  ## Quick start

      # In your router:
      live "/tui", MyAppWeb.MyTuiLive

      # Anywhere else (typically lib/my_app_web/live/):
      defmodule MyAppWeb.MyTuiLive do
        use PhoenixExRatatui.LiveView, app: MyApp.Tui
      end

  That's it. Visit `/tui` and the App runs in the browser. The
  generated LiveView mounts a `<div phx-hook="PhoenixExRatatuiHook">`,
  the JS hook (in this package's bundled assets) measures its cell
  grid, reports dimensions back to the server, and the
  `PhoenixExRatatui.Transport` starts an `ExRatatui.Server` driving
  `MyApp.Tui` against an `ExRatatui.CellSession` at the reported size.
  Frame diffs ship to the hook as `push_event/3` payloads encoded by
  `PhoenixExRatatui.Renderer.Html`; client input flows back as
  `phx_ex_ratatui:input` events.

  ## Lifecycle

  - **HTTP mount** (not `connected?`) — empty assigns, render the hook
    container, no Transport. Per `phoenix-thinking`'s no-work-in-mount
    rule: HTTP mount runs twice (once for the static render, once for
    the WebSocket handshake), so we never start the server here.
  - **WebSocket mount** — `Process.flag(:trap_exit, true)` is set so a
    mount-failing TUI app returns `{:error, _}` cleanly from
    `Transport.start_link/1` instead of killing the LV (which would
    trigger an infinite client reconnect loop). Initial assigns set
    `:tui` to `nil`; the Transport starts on the first `"resize"`
    event from the hook.
  - **Hook reports size** (`phx_ex_ratatui:resize`) — first time:
    start the Transport at `{cols, rows}`. Subsequent times: call
    `Transport.resize/3`, which both resizes the underlying
    `CellSession` and notifies the runtime so the App's
    `handle_event/2` sees a `%ExRatatui.Event.Resize{}` and the next
    diff payload is full at the new dimensions.
  - **Hook reports input** (`phx_ex_ratatui:input`) — decoded into an
    `%ExRatatui.Event.Key{}` (or `%Event.Mouse{}` once that path
    lands) and forwarded to the runtime via `Transport.push_event/2`.
  - **Runtime emits a frame** (`{:phoenix_ex_ratatui, :render, diff}`) —
    encoded via `Renderer.Html.encode_diff/1` and pushed to the hook
    as a `phx_ex_ratatui:render` event.
  - **LiveView exits** — the linked `ExRatatui.Server` runs its own
    `terminate/2` (closes the `CellSession`, calls user `terminate/2`,
    emits transport-disconnect telemetry). LiveView's `terminate/3` is
    deliberately not relied on; per `phoenix-thinking`, it only fires
    when the socket traps exits, which is unusual and brittle.

  ## Options

    * `:app` (required) — module implementing `ExRatatui.App` to drive.
    * `:container_id` — DOM id for the hook container. Defaults to
      `"phoenix-ex-ratatui"`. Override when embedding multiple TUI
      pages on the same router so the JS hook's `getElementById`
      queries don't collide.

  ## Customising

  The generated callbacks are marked `defoverridable`, so you can wrap
  any of them with your own behaviour and call `super(...)`:

      defmodule MyAppWeb.MyTuiLive do
        use PhoenixExRatatui.LiveView, app: MyApp.Tui

        @impl true
        def mount(params, session, socket) do
          {:ok, socket} = super(params, session, socket)
          {:ok, assign(socket, :current_user, session["user_id"])}
        end
      end

  For deeper customisation (custom render, embedding alongside other
  content), reach for `PhoenixExRatatui.LiveComponent` instead of this
  macro.
  """

  alias ExRatatui.Event.Key
  alias PhoenixExRatatui.Renderer.Html
  alias PhoenixExRatatui.Telemetry
  alias PhoenixExRatatui.Transport

  @doc """
  Decodes the `phx_ex_ratatui:input` payload the JS hook sends into an
  `t:ExRatatui.Event.t/0`.

  Exposed `pub` so users hand-rolling their own LiveView (without the
  `__using__` macro) can reuse the same shape contract the bundled JS
  hook speaks.

  Modifier strings are converted with `String.to_existing_atom/1` —
  the atoms (`:ctrl`, `:alt`, `:shift`, `:super`, `:hyper`, `:meta`)
  are pre-loaded by `ExRatatui.Event.Key`, so untrusted client input
  cannot grow the atom table.
  """
  @spec decode_input(map()) :: ExRatatui.Event.t()
  def decode_input(%{"kind" => "key"} = params) do
    %Key{
      code: Map.fetch!(params, "code"),
      modifiers: decode_modifiers(Map.get(params, "modifiers", [])),
      kind: Map.get(params, "press_kind", "press")
    }
  end

  defp decode_modifiers(modifiers) when is_list(modifiers) do
    Enum.map(modifiers, &String.to_existing_atom/1)
  end

  @doc """
  Generates the full-page LiveView. See the moduledoc.
  """
  defmacro __using__(opts) do
    # Macro body is intentionally one line: macro-expansion code is
    # compile-time and `mix test --cover` does not track it (cover
    # instrumentation activates after lib/ has already compiled). By
    # delegating to a regular function we keep the option-parsing
    # path trackable via a runtime test, while preserving identical
    # macro semantics for users.
    __build_using_quote__(opts)
  end

  @doc false
  # Builds the quoted block injected into a user's module at compile
  # time. Public-but-undocumented (`@doc false`) so the test suite
  # can call it directly to verify option handling without going
  # through compile-time macro expansion.
  #
  # The quote block contains seven user-module callbacks (mount,
  # render, two handle_event clauses, handle_info, defoverridable),
  # which credo's cyclomatic-complexity scan counts as branches even
  # though they're inert AST data inside this function — disabled
  # because rewriting the quote in smaller pieces and stitching them
  # together hurts readability for no real complexity reduction.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def __build_using_quote__(opts) do
    app = Keyword.fetch!(opts, :app)
    container_id = Keyword.get(opts, :container_id, "phoenix-ex-ratatui")

    quote location: :keep do
      use Phoenix.LiveView

      @phoenix_ex_ratatui_app unquote(app)
      @phoenix_ex_ratatui_container_id unquote(container_id)

      @impl Phoenix.LiveView
      def mount(_params, _session, socket) do
        if Phoenix.LiveView.connected?(socket) do
          # See moduledoc — without trap_exit a mount-failing TUI app
          # would kill the LV and infinite-reconnect from the client.
          Process.flag(:trap_exit, true)
        end

        # Fully-qualify `Phoenix.Component.assign/3` because users of
        # `tui_live` get this code expanded inside their router's
        # compile context, where `Plug.Conn.assign/3` is also
        # imported and the bare call is ambiguous. Hand-rolled LV
        # modules don't hit this — they don't import Plug.Conn —
        # but we have to support both call sites.
        socket =
          socket
          |> Phoenix.Component.assign(:tui, nil)
          |> Phoenix.Component.assign(:tui_error, nil)
          |> Phoenix.Component.assign(:tui_ended, false)
          |> Phoenix.Component.assign(:tui_app, @phoenix_ex_ratatui_app)
          |> Phoenix.Component.assign(:tui_container_id, @phoenix_ex_ratatui_container_id)

        {:ok, socket}
      end

      @impl Phoenix.LiveView
      def render(var!(assigns)) do
        # The `phx-update="ignore"` on the hook container is critical:
        # the JS hook owns the cell-grid DOM after mount. We render
        # any TUI error message in a SIBLING block so LV can update
        # it without fighting the hook for control of the container's
        # children.
        ~H"""
        <div
          id={@tui_container_id}
          phx-hook="PhoenixExRatatuiHook"
          phx-update="ignore"
          data-phx-ex-ratatui-app={inspect(@tui_app)}
          style="width:100%;height:100vh"
        >
        </div>
        <%= if @tui_error do %>
          <p class="phoenix-ex-ratatui-error">TUI error: {@tui_error}</p>
        <% end %>
        <%= if @tui_ended do %>
          <p class="phoenix-ex-ratatui-ended" style="position:fixed;top:1rem;right:1rem;padding:0.5rem 1rem;background:#222;border:1px solid #555;border-radius:4px;">
            TUI session ended. <a href="" style="color:#729fcf;">Refresh</a> to restart.
          </p>
        <% end %>
        """
      end

      @impl Phoenix.LiveView
      def handle_event(
            "phx_ex_ratatui:resize",
            %{"cols" => cols, "rows" => rows},
            socket
          )
          when is_integer(cols) and cols > 0 and is_integer(rows) and rows > 0 do
        {:noreply, PhoenixExRatatui.LiveView.__handle_resize__(socket, cols, rows)}
      end

      def handle_event("phx_ex_ratatui:input", payload, socket) when is_map(payload) do
        {:noreply, PhoenixExRatatui.LiveView.__handle_input__(socket, payload)}
      end

      @impl Phoenix.LiveView
      def handle_info({:phoenix_ex_ratatui, :render, diff}, socket) do
        {:noreply,
         PhoenixExRatatui.LiveView.__push_render__(socket, @phoenix_ex_ratatui_app, diff)}
      end

      # The runtime server is linked to this LV (via Transport.start_link).
      # When the App returns `{:stop, _}`, the server exits cleanly and
      # we get an EXIT signal. Without this clause the painted cells
      # stay on screen but no events flow — a confusing "frozen TUI"
      # state. We catch the EXIT, null out the refs, and flip
      # `:tui_ended` so render/1 shows a refresh prompt.
      def handle_info({:EXIT, server_pid, _reason}, socket) do
        {:noreply, PhoenixExRatatui.LiveView.__handle_server_exit__(socket, server_pid)}
      end

      defoverridable mount: 3, render: 1, handle_event: 3, handle_info: 2
    end
  end

  @doc false
  # Internal helper for the resize event handler — kept on the parent
  # module rather than expanded into every user's `__using__` so the
  # generated code stays small and clippy/credo-clean.
  def __handle_resize__(socket, cols, rows) do
    case socket.assigns.tui do
      nil -> __start_transport__(socket, cols, rows)
      refs -> __resize_transport__(socket, refs, cols, rows)
    end
  end

  defp __start_transport__(socket, cols, rows) do
    case Transport.start_link(
           mod: socket.assigns.tui_app,
           width: cols,
           height: rows,
           target: self()
         ) do
      {:ok, refs} ->
        Phoenix.Component.assign(socket, :tui, refs)

      {:error, reason} ->
        Phoenix.Component.assign(socket, :tui_error, inspect(reason))
    end
  end

  defp __resize_transport__(socket, refs, cols, rows) do
    case Transport.resize(refs, cols, rows) do
      :ok -> socket
      {:error, _} -> Phoenix.Component.assign(socket, :tui_error, "session closed")
    end
  end

  @doc false
  # Detect when the linked runtime server has exited and surface the
  # "TUI session ended" state to the user. We match on the server pid
  # via the assigns to ignore EXIT signals from any unrelated linked
  # process (e.g. a user-opened Task in their own mount/3 override).
  def __handle_server_exit__(socket, server_pid) do
    case socket.assigns[:tui] do
      %{server: ^server_pid} ->
        socket
        |> Phoenix.Component.assign(:tui, nil)
        |> Phoenix.Component.assign(:tui_ended, true)

      _ ->
        socket
    end
  end

  @doc false
  # Internal helper for the render-frame info message. Encoding the
  # diff lives here (rather than inline in the macro-generated
  # handle_info) so the quote block doesn't carry a fully-qualified
  # reference to PhoenixExRatatui.Renderer.Html — keeps the macro
  # output small and the module aliases tidy. Wraps the encode +
  # push_event work in a `[:phoenix_ex_ratatui, :render, :frame]`
  # span so per-frame Phoenix-side cost is observable in metrics.
  def __push_render__(socket, mod, diff) do
    meta = %{mod: mod, width: diff.width, height: diff.height, ops_count: length(diff.ops)}

    Telemetry.span([:render, :frame], meta, fn ->
      Phoenix.LiveView.push_event(socket, "phx_ex_ratatui:render", Html.encode_diff(diff))
    end)
  end

  @doc false
  # Internal helper for the input event handler. Emits a
  # `[:phoenix_ex_ratatui, :input, :forward]` event so consumers can
  # count input rates / latencies; the actual push_event/2 to the
  # runtime is forwarded after the telemetry call so a slow handler
  # never blocks input dispatch.
  def __handle_input__(socket, payload) do
    case socket.assigns.tui do
      nil ->
        # Hook fired input before the resize — odd but possible during
        # browser resize storms. Drop it; the Transport isn't started
        # yet so there's nowhere to send it. The next render will
        # repaint and the user can retry the input.
        socket

      refs ->
        event = decode_input(payload)
        Telemetry.execute([:input, :forward], %{}, %{mod: refs.mod, event: event})
        :ok = Transport.push_event(refs, event)
        socket
    end
  end
end

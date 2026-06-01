defmodule PhoenixExRatatui.LiveView do
  @moduledoc """
  Macro that turns the calling module into a full-page TUI route — the
  same module is both a `Phoenix.LiveView` and the `ExRatatui.App` that
  drives it.

  ## Quick start

      # In the router (no special macro needed):
      live "/tui", MyAppWeb.MyTuiLive

      # The live module:
      defmodule MyAppWeb.MyTuiLive do
        use PhoenixExRatatui.LiveView
        alias ExRatatui.Layout.Rect
        alias ExRatatui.Widgets.Paragraph

        def tui_mount(_opts), do: {:ok, %{count: 0}}

        def tui_render(state, frame) do
          [{%Paragraph{text: "Count: \#{state.count}"},
            %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
        end

        def tui_handle_event(%ExRatatui.Event.Key{code: "+"}, state),
          do: {:noreply, %{state | count: state.count + 1}}

        def tui_handle_event(%ExRatatui.Event.Key{code: "q"}, state),
          do: {:stop, state}

        def tui_handle_event(_event, state), do: {:noreply, state}
      end

  ## How it works

  `use PhoenixExRatatui.LiveView` injects a full `Phoenix.LiveView`
  implementation (mount/3, render/1, handle_event/3, handle_info/2)
  AND, via `@after_compile`, generates a sibling
  `MyAppWeb.MyTuiLive.Runtime` module that implements `ExRatatui.App`
  by delegating to the `tui_*` callbacks on the calling module.

  The runtime proxy exists because `Phoenix.LiveView.handle_info/2`
  (msg, socket) and `ExRatatui.App.handle_info/2` (msg, state) collide
  on arity. Splitting the App into a hidden submodule lets both
  behaviours live side-by-side without renaming Phoenix LV callbacks.

  The proxy needs no attention — define the `tui_*` callbacks and the
  macro handles the rest.

  ## TUI callbacks (override as needed)

    * `tui_mount(opts)` — return `{:ok, state}`, `{:ok, state,
      runtime_opts}`, or `{:error, reason}`. `opts` is the keyword
      list returned by `tui_mount_opts/1`.
    * `tui_render(state, frame)` — return a list of `{widget, rect}`
      tuples. Default: `[]`.
    * `tui_handle_event(event, state)` — return `{:noreply, state}` or
      `{:stop, state}`. Default: `{:noreply, state}`.
    * `tui_handle_info(msg, state)` — same shape; for messages sent to
      the runtime server (PubSub, `send/2`). Default: `{:noreply, state}`.
    * `tui_terminate(reason, state)` — cleanup. Default: `:ok`.
    * `tui_mount_opts(socket)` — return the keyword list passed as
      `opts` to `tui_mount/1`. Use this to thread per-connection
      context (current user, params) from `Phoenix.LiveView` assigns
      into the App. Default: `[]`.

  ## Threading socket data into the App

  `tui_mount_opts/1` is the bridge:

      defmodule MyAppWeb.AdminTui do
        use PhoenixExRatatui.LiveView

        @impl Phoenix.LiveView
        def mount(_params, session, socket) do
          {:ok, socket} = super(nil, nil, socket)
          {:ok, Phoenix.Component.assign(socket, :user_id, session["user_id"])}
        end

        def tui_mount_opts(socket), do: [user_id: socket.assigns.user_id]

        def tui_mount(opts), do: {:ok, %{user_id: opts[:user_id], n: 0}}
      end

  ## Lifecycle

  - **HTTP mount** (not `connected?`) — empty assigns, render hook
    container, no Transport. Per `phoenix-thinking`'s no-work-in-mount
    rule: `mount/3` runs twice (HTTP request + WebSocket handshake).
  - **WebSocket mount** — `Process.flag(:trap_exit, true)` so a
    mount-failing TUI returns `{:error, _}` cleanly from
    `Transport.start_link/1` instead of killing the LV (which would
    trigger an infinite client reconnect loop).
  - **First `phx_ex_ratatui:resize`** — call `tui_mount_opts/1`, start
    the Transport at `{cols, rows}` driving the generated `Runtime`
    proxy.
  - **Subsequent resizes** — `Transport.resize/3` updates the
    `CellSession` and notifies the runtime.
  - **Hook input** — decoded into an `%ExRatatui.Event.Key{}` and
    forwarded via `Transport.push_event/2`.
  - **Runtime emits a frame** — encoded via
    `PhoenixExRatatui.Renderer.Html.encode_diff/1` and pushed as
    a `phx_ex_ratatui:render` event.
  - **Runtime exits** (App returned `{:stop, _}`, or crash) — we get
    an EXIT signal, null out `:tui`, set `:tui_ended` so the user
    sees a refresh prompt instead of a frozen-cells display.

  ## Options

    * `:container_id` — DOM id for the hook container. Defaults to
      `"phoenix-ex-ratatui"`. Override when embedding multiple TUI
      pages on the same router so the JS hook's `getElementById`
      queries don't collide.
    * `:runtime` — `:callbacks` (default) or `:reducer`. Selects the
      `ExRatatui.App` runtime style used by the generated proxy.
      Reducer-runtime modules implement `tui_init/1`, `tui_render/2`,
      `tui_update/2` (with `{:event, _}` / `{:info, _}` wrapped
      messages), and optionally `tui_subscriptions/1`, instead of the
      callbacks-runtime `tui_mount/1` / `tui_handle_event/2` /
      `tui_handle_info/2` quartet. See
      [ExRatatui.App](`ExRatatui.App`) for the runtime distinction.

  ## Customising LiveView callbacks

  All LiveView callbacks (`mount/3`, `render/1`, `handle_event/3`,
  `handle_info/2`) are `defoverridable`. You can wrap any of them and
  call `super(...)`:

      def mount(params, session, socket) do
        {:ok, socket} = super(params, session, socket)
        {:ok, assign(socket, :title, "My TUI")}
      end

  For mixed pages where the TUI is one of several pieces of UI,
  reach for `PhoenixExRatatui.LiveComponent` instead.
  """

  alias ExRatatui.Event.Key
  alias PhoenixExRatatui.Renderer.Html
  alias PhoenixExRatatui.Telemetry
  alias PhoenixExRatatui.Transport

  @doc """
  Decodes the `phx_ex_ratatui:input` payload the JS hook sends into an
  `t:ExRatatui.Event.t/0`.

  Modifier strings are converted with `String.to_existing_atom/1` —
  the atoms (`:ctrl`, `:alt`, `:shift`, `:super`, `:hyper`, `:meta`)
  are pre-loaded by `ExRatatui.Event.Key`, so untrusted client input
  cannot grow the atom table.

  ## Examples

      iex> event = PhoenixExRatatui.LiveView.decode_input(%{"kind" => "key", "code" => "a", "modifiers" => ["ctrl"]})
      iex> {event.code, event.modifiers, event.kind}
      {"a", [:ctrl], "press"}
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
  Generates the unified LiveView + App module. See the moduledoc.
  """
  defmacro __using__(opts) do
    # Macro body delegates to a regular function so the option-parsing
    # path is trackable by `mix test --cover` (cover instrumentation
    # doesn't see compile-time macro execution).
    __build_using_quote__(opts)
  end

  @doc false
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def __build_using_quote__(opts) do
    container_id = Keyword.get(opts, :container_id, "phoenix-ex-ratatui")
    runtime = Keyword.get(opts, :runtime, :callbacks)

    unless runtime in [:callbacks, :reducer] do
      raise ArgumentError,
            "PhoenixExRatatui.LiveView :runtime must be :callbacks or :reducer, got: #{inspect(runtime)}"
    end

    tui_defaults = tui_defaults_quote(runtime)

    quote location: :keep do
      use Phoenix.LiveView

      @phoenix_ex_ratatui_container_id unquote(container_id)
      @phoenix_ex_ratatui_runtime_mod Module.concat(__MODULE__, "Runtime")
      @phoenix_ex_ratatui_runtime unquote(runtime)

      # ----- TUI callback defaults (all overridable) -----
      unquote(tui_defaults)

      # ----- Phoenix.LiveView callbacks -----

      @impl Phoenix.LiveView
      def mount(_params, _session, socket) do
        if Phoenix.LiveView.connected?(socket) do
          # Without trap_exit a mount-failing TUI app would kill the LV
          # and infinite-reconnect from the client.
          Process.flag(:trap_exit, true)
        end

        socket =
          socket
          |> Phoenix.Component.assign(:tui, nil)
          |> Phoenix.Component.assign(:tui_error, nil)
          |> Phoenix.Component.assign(:tui_ended, false)
          |> Phoenix.Component.assign(:tui_container_id, @phoenix_ex_ratatui_container_id)
          |> Phoenix.Component.assign(:tui_runtime_mod, @phoenix_ex_ratatui_runtime_mod)

        {:ok, socket}
      end

      @impl Phoenix.LiveView
      def render(var!(assigns)) do
        ~H"""
        <div
          id={@tui_container_id}
          phx-hook="PhoenixExRatatuiHook"
          phx-update="ignore"
          data-phx-ex-ratatui-runtime={inspect(@tui_runtime_mod)}
          data-phx-ex-ratatui-autofocus="true"
          style="width:100%;height:100vh"
        >
        </div>
        <%= if @tui_error do %>
          <p class="phoenix-ex-ratatui-error">TUI error: {@tui_error}</p>
        <% end %>
        <%= if @tui_ended do %>
          <p class="phoenix-ex-ratatui-ended" style="position:fixed;top:1rem;right:1rem;margin:0;padding:0.5rem 0.85rem;background:#0f0c14;border:1px solid #75507b;border-radius:4px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:0.85rem;color:#e9e4f5;box-shadow:0 0 0 1px #0f0c14, 0 4px 18px rgba(0,0,0,0.4);">
            🖥️  <span style="color:#ad7fa8;">~$</span> tui session ended.
            <a href="" style="color:#ad7fa8;text-decoration:underline;">[refresh]</a> to restart.
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
        {:noreply, PhoenixExRatatui.LiveView.__handle_resize__(socket, __MODULE__, cols, rows)}
      end

      def handle_event("phx_ex_ratatui:input", payload, socket) when is_map(payload) do
        {:noreply, PhoenixExRatatui.LiveView.__handle_input__(socket, payload)}
      end

      @impl Phoenix.LiveView
      def handle_info({:phoenix_ex_ratatui, :render, diff}, socket) do
        {:noreply,
         PhoenixExRatatui.LiveView.__push_render__(socket, @phoenix_ex_ratatui_runtime_mod, diff)}
      end

      def handle_info({:phoenix_ex_ratatui, :intent, intent}, socket) do
        {:noreply, PhoenixExRatatui.LiveView.__handle_intent__(socket, intent)}
      end

      def handle_info({:EXIT, server_pid, _reason}, socket) do
        {:noreply, PhoenixExRatatui.LiveView.__handle_server_exit__(socket, server_pid)}
      end

      defoverridable mount: 3, render: 1, handle_event: 3, handle_info: 2

      # Generates the sibling `__MODULE__.Runtime` proxy that conforms
      # to `ExRatatui.App` by delegating to this module's `tui_*`
      # callbacks. See the moduledoc for the rationale.
      @after_compile {PhoenixExRatatui.LiveView, :__define_runtime__}
    end
  end

  @doc false
  # Quoted block injected for `tui_*` callback defaults. The shape
  # depends on the runtime style — callbacks-runtime uses
  # mount/handle_event/handle_info, reducer-runtime uses
  # init/update/subscriptions wrapping `{:event, _}` / `{:info, _}`.
  def tui_defaults_quote(:callbacks) do
    quote do
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
    end
  end

  def tui_defaults_quote(:reducer) do
    quote do
      @doc false
      def tui_init(_opts), do: {:ok, %{}}

      @doc false
      def tui_render(_state, _frame), do: []

      @doc false
      def tui_update(_msg, state), do: {:noreply, state}

      @doc false
      def tui_subscriptions(_state), do: []

      @doc false
      def tui_terminate(_reason, _state), do: :ok

      @doc false
      def tui_mount_opts(_socket), do: []

      defoverridable tui_init: 1,
                     tui_render: 2,
                     tui_update: 2,
                     tui_subscriptions: 1,
                     tui_terminate: 2,
                     tui_mount_opts: 1
    end
  end

  @doc false
  # Compile-time hook called via `@after_compile`. Builds a sibling
  # module (`UserMod.Runtime`) that uses `ExRatatui.App` and delegates
  # every behaviour callback to the user module's `tui_*` functions.
  # This lets the unified module appear to implement both behaviours
  # without colliding on `handle_info/2` (same arity, different
  # semantics).
  def __define_runtime__(env, _bytecode) do
    user_mod = env.module
    runtime = Module.get_attribute(user_mod, :phoenix_ex_ratatui_runtime, :callbacks)
    runtime_mod = Module.concat(user_mod, "Runtime")

    body = proxy_body(runtime, user_mod)

    Module.create(runtime_mod, body, file: env.file, line: env.line)
    :ok
  end

  defp proxy_body(:callbacks, user_mod) do
    quote do
      use ExRatatui.App

      @impl ExRatatui.App
      def mount(opts), do: unquote(user_mod).tui_mount(opts)

      @impl ExRatatui.App
      def render(state, frame), do: unquote(user_mod).tui_render(state, frame)

      @impl ExRatatui.App
      def handle_event(event, state),
        do: unquote(user_mod).tui_handle_event(event, state)

      @impl ExRatatui.App
      def handle_info(msg, state),
        do: unquote(user_mod).tui_handle_info(msg, state)

      @impl ExRatatui.App
      def terminate(reason, state),
        do: unquote(user_mod).tui_terminate(reason, state)
    end
  end

  defp proxy_body(:reducer, user_mod) do
    quote do
      use ExRatatui.App, runtime: :reducer

      @impl ExRatatui.App
      def init(opts), do: unquote(user_mod).tui_init(opts)

      @impl ExRatatui.App
      def render(state, frame), do: unquote(user_mod).tui_render(state, frame)

      @impl ExRatatui.App
      def update(msg, state), do: unquote(user_mod).tui_update(msg, state)

      @impl ExRatatui.App
      def subscriptions(state), do: unquote(user_mod).tui_subscriptions(state)

      @impl ExRatatui.App
      def terminate(reason, state),
        do: unquote(user_mod).tui_terminate(reason, state)
    end
  end

  @doc false
  def __handle_resize__(socket, user_mod, cols, rows) do
    case socket.assigns.tui do
      nil -> __start_transport__(socket, user_mod, cols, rows)
      refs -> __resize_transport__(socket, refs, cols, rows)
    end
  end

  defp __start_transport__(socket, user_mod, cols, rows) do
    runtime_mod = Module.concat(user_mod, "Runtime")
    mount_opts = user_mod.tui_mount_opts(socket)

    start_link_opts =
      [
        mod: runtime_mod,
        width: cols,
        height: rows,
        target: self()
      ] ++ mount_opts

    case Transport.start_link(start_link_opts) do
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
  def __push_render__(socket, mod, diff) do
    meta = %{mod: mod, width: diff.width, height: diff.height, ops_count: length(diff.ops)}

    Telemetry.span([:render, :frame], meta, fn ->
      Phoenix.LiveView.push_event(socket, "phx_ex_ratatui:render", Html.encode_diff(diff))
    end)
  end

  @doc """
  Dispatches a runtime intent against a LiveView socket.

  Intents are emitted by an `ExRatatui.App` from `tui_handle_event/2`
  or `tui_handle_info/2` via the third element of a `{:noreply, state,
  intents: [...]}` (or `{:stop, ...}`) transition. They flow through
  `ExRatatui.Server`'s `intent_writer_fn` to this LV, where this
  helper maps the intent shape to the equivalent Phoenix LV action.

  Recognised intents:

    * `{:navigate, path}` — `Phoenix.LiveView.push_navigate(socket, to: path)`
    * `{:patch, path}` — `Phoenix.LiveView.push_patch(socket, to: path)`
    * `{:redirect, path}` — `Phoenix.LiveView.redirect(socket, to: path)`
    * `{:redirect, [external: url]}` — external redirect

  Unrecognised intents are dropped and logged at warning level. This
  keeps a TUI app forward-compatible: a future intent the consumer
  doesn't know how to handle yet won't crash the LV.

  Public so `PhoenixExRatatui.LiveComponent` can reuse the same
  dispatch table.
  """
  @spec dispatch_intent(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def dispatch_intent(socket, {:navigate, path}) when is_binary(path) do
    Phoenix.LiveView.push_navigate(socket, to: path)
  end

  def dispatch_intent(socket, {:patch, path}) when is_binary(path) do
    Phoenix.LiveView.push_patch(socket, to: path)
  end

  def dispatch_intent(socket, {:redirect, path}) when is_binary(path) do
    Phoenix.LiveView.redirect(socket, to: path)
  end

  def dispatch_intent(socket, {:redirect, [external: url]}) when is_binary(url) do
    Phoenix.LiveView.redirect(socket, external: url)
  end

  def dispatch_intent(socket, intent) do
    require Logger
    Logger.warning("phoenix_ex_ratatui: dropped unrecognised intent #{inspect(intent)}")
    socket
  end

  @doc false
  def __handle_intent__(socket, intent) do
    Telemetry.execute([:intent, :dispatch], %{}, %{intent: intent})
    dispatch_intent(socket, intent)
  end

  @doc false
  def __handle_input__(socket, payload) do
    case socket.assigns.tui do
      nil ->
        socket

      refs ->
        event = decode_input(payload)
        Telemetry.execute([:input, :forward], %{}, %{mod: refs.mod, event: event})
        :ok = Transport.push_event(refs, event)
        socket
    end
  end
end

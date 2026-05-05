defmodule PhoenixExRatatui.Transport do
  @moduledoc """
  Connection-level helper that wires an `ExRatatui.App` to a
  `Phoenix.LiveView` (or `Phoenix.LiveComponent`) over a freshly
  constructed `ExRatatui.CellSession`.

  Implements the `ExRatatui.Transport` behaviour as a marker — Phoenix
  doesn't supervise transports the way `ExRatatui.SSH.Daemon` does, so
  there's no `child_spec/1`. Each LiveView mount calls `start_link/1`
  with `target: self()`, holds onto the returned `%{server, cell_session}`
  references in its assigns, and pattern-matches on the rendered
  `%CellSession.Diff{}` payloads in `handle_info/2`.

  ## Wire protocol

  Outbound (server → LiveView):

      {:phoenix_ex_ratatui, :render, %ExRatatui.CellSession.Diff{}}

  Inbound (LiveView → server) — same as every byte-stream transport:

      {:ex_ratatui_event, %ExRatatui.Event.t{}}
      {:ex_ratatui_resize, w, h}

  Use `push_event/2` and `resize/3` rather than sending those messages
  by hand — both also handle the `CellSession.resize/3` step that must
  precede a resize message.

  ## Example mount

      def mount(_params, _session, socket) do
        if connected?(socket) do
          {:ok, refs} =
            PhoenixExRatatui.Transport.start_link(
              mod: MyApp,
              width: 80,
              height: 24,
              target: self()
            )

          {:ok, assign(socket, tui: refs)}
        else
          {:ok, assign(socket, tui: nil)}
        end
      end

      def handle_info({:phoenix_ex_ratatui, :render, diff}, socket) do
        {:noreply, push_event(socket, "render", encode_for_client(diff))}
      end

  The server is started linked to the caller. When the LiveView process
  exits (browser disconnect, navigation, crash), the server's
  `terminate/2` runs deterministically: closes the `CellSession`, calls
  the user `terminate/2`, emits transport-disconnect telemetry. We do
  not rely on `Phoenix.LiveView.terminate/2` (which only fires when the
  socket is `trap_exit`-aware, and we don't recommend that).
  """

  @behaviour ExRatatui.Transport

  alias ExRatatui.CellSession
  alias ExRatatui.CellSession.Diff

  @typedoc """
  References returned from `start_link/1`. Hold onto both — the
  `:server` pid for `push_event/2` and `stop/2`, the `:cell_session`
  for `resize/3` (which must resize the session before notifying the
  server).
  """
  @type refs :: %{server: pid(), cell_session: CellSession.t()}

  @doc """
  Constructs an `ExRatatui.CellSession` at `width x height` and starts
  an `ExRatatui.Server` driving `mod` against it. The server ships
  rendered cell diffs to `target` as
  `{:phoenix_ex_ratatui, :render, %CellSession.Diff{}}` messages.

  ## Options

    * `:mod` (required) — module implementing `ExRatatui.App`.
    * `:width` (required) — initial terminal width in cells. Must be `>= 1`.
    * `:height` (required) — initial terminal height in cells. Must be `>= 1`.
    * `:target` (required) — `t:pid/0` that should receive rendered
      `%Diff{}` messages. Typically `self()` from a LiveView mount.
    * Any other option — passed through verbatim to `mod.mount/1`. Use
      this to thread per-connection context (current user, params,
      LiveView socket id) into the App without a global registry.

  ## Return shape

      {:ok, %{server: server_pid, cell_session: %CellSession{}}}

  Returns whatever error tuple `mod.mount/1` produced if mount fails;
  the `CellSession` is closed defensively before propagating.

  The server is **linked** to the calling process. When the LiveView
  exits, the server's `terminate/2` runs and closes the session.
  """
  @spec start_link(keyword()) :: {:ok, refs()} | {:error, term()}
  def start_link(opts) when is_list(opts) do
    target = Keyword.fetch!(opts, :target)
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    mod = Keyword.fetch!(opts, :mod)

    unless is_pid(target) and is_integer(width) and width > 0 and is_integer(height) and
             height > 0 do
      raise ArgumentError,
            "expected :target as pid and :width / :height as positive integers, got: " <>
              inspect(target: target, width: width, height: height)
    end

    pass_through_opts = Keyword.drop(opts, [:target, :width, :height, :mod, :transport, :name])

    cell_session = CellSession.new(width, height)
    writer_fn = build_writer(target)

    server_opts =
      [
        mod: mod,
        name: nil,
        transport: {:cell_session, cell_session, writer_fn}
      ] ++ pass_through_opts

    case ExRatatui.Transport.start_server(server_opts) do
      {:ok, server} ->
        {:ok, %{server: server, cell_session: cell_session}}

      {:error, _reason} = err ->
        # Belt-and-braces: the Server's `continue_init_cell_session`
        # already closes the session on mount failure, but if the
        # error came from before that point (or returned from a
        # future code path that doesn't), we don't want to leak the
        # NIF resource.
        CellSession.close(cell_session)
        err
    end
  end

  @doc """
  Sends a decoded terminal event to the runtime server. Wrapper around
  the `{:ex_ratatui_event, _}` mailbox protocol so callers don't have
  to know the message tag.

  Used by the LiveView's client-side hook to forward keypresses, mouse
  clicks, and synthetic events from the browser into the App's
  `handle_event/2`.
  """
  @spec push_event(pid() | refs(), ExRatatui.Event.t()) :: :ok
  def push_event(server, event) when is_pid(server) do
    send(server, {:ex_ratatui_event, event})
    :ok
  end

  def push_event(%{server: server}, event), do: push_event(server, event)

  @doc """
  Resizes the underlying `CellSession` and notifies the server so the
  next render uses the new dimensions.

  The two operations happen in this order on purpose: the server's
  resize handler updates the cached size *before* the next render,
  but it does not touch the session itself — that's the transport's
  job. Calling `resize/3` here gets it right; sending
  `{:ex_ratatui_resize, _, _}` directly to the server would leave the
  session stuck at the old size and the next `take_cells_diff/1`
  would emit a stale full payload.

  Returns `{:error, reason}` if `CellSession.resize/3` fails (e.g. the
  session was already closed); the server is not notified in that case.
  """
  @spec resize(refs(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def resize(%{server: server, cell_session: cell_session}, width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    case CellSession.resize(cell_session, width, height) do
      :ok ->
        send(server, {:ex_ratatui_resize, width, height})
        :ok

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Stops the runtime server cleanly. The `CellSession` is closed by the
  server's `terminate/2`; no separate cleanup is needed.

  Idempotent in the practical sense: calling `stop/2` after the server
  has already exited is harmless (the call returns immediately). For
  graceful shutdown from a LiveView's `terminate/3`, prefer relying on
  the link — letting the LiveView exit naturally tears down the server
  via the standard EXIT path.
  """
  @spec stop(refs(), term()) :: :ok
  def stop(%{server: server}, reason \\ :normal) do
    if Process.alive?(server) do
      GenServer.stop(server, reason)
    else
      :ok
    end
  end

  # The writer_fn handed to ExRatatui.Server. Called from the server
  # process on every render with the freshly-extracted diff. We forward
  # it verbatim to the LiveView; encoding to JSON for `push_event/3`
  # happens in the LiveView itself (PhoenixExRatatui.Renderer.Html in
  # a follow-up chunk), so the wire payload here stays a struct.
  defp build_writer(target_pid) when is_pid(target_pid) do
    fn %Diff{} = diff ->
      send(target_pid, {:phoenix_ex_ratatui, :render, diff})
      :ok
    end
  end
end

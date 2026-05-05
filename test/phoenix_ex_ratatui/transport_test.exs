defmodule PhoenixExRatatui.TransportTest do
  @moduledoc """
  Tests for the Phoenix-side transport helper. We don't stand up a
  real LiveView here — the helper is supposed to work with `target:
  self()` from any process, and that's what the LiveView mount will
  pass. Asserting from a plain test process catches everything that
  matters at this layer (writer callback wiring, link semantics,
  resize coordination, mount-failure cleanup).
  """

  use ExUnit.Case, async: true

  alias ExRatatui.CellSession
  alias ExRatatui.CellSession.Diff
  alias ExRatatui.Event.Key
  alias PhoenixExRatatui.FailingMountApp
  alias PhoenixExRatatui.TestApp
  alias PhoenixExRatatui.Transport

  describe "start_link/1" do
    test "boots the runtime, ships the first frame, and returns refs" do
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 40,
          height: 6,
          target: self(),
          test_pid: self()
        )

      assert %{server: server, cell_session: %CellSession{}} = refs
      assert is_pid(server)
      assert Process.alive?(server)

      # mount/1 sees the augmented opts populated by ExRatatui.Server.
      assert_receive {:mounted, opts}, 1000
      assert opts[:transport] == :cell_session
      assert opts[:width] == 40
      assert opts[:height] == 6
      assert opts[:test_pid] == self()

      # The first render's diff carries every cell — there's no prior
      # baseline, so take_cells_diff/1 emits the full grid.
      assert_receive {:phoenix_ex_ratatui, :render, %Diff{} = diff}, 1000
      assert diff.width == 40
      assert diff.height == 6
      assert length(diff.ops) == 40 * 6

      Transport.stop(refs)
    end

    test "passes through extra opts to mod.mount/1" do
      # Anything not in the reserved set (mod/width/height/target/
      # transport/name) reaches mount/1 unchanged. Lets the caller
      # thread per-connection context (current_user, params, …) into
      # the App without a global registry.
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 2,
          target: self(),
          test_pid: self(),
          custom_opt: :hello
        )

      assert_receive {:mounted, opts}, 1000
      assert opts[:custom_opt] == :hello

      Transport.stop(refs)
    end

    test "raises ArgumentError on invalid dimensions" do
      assert_raise ArgumentError, ~r/positive integers/, fn ->
        Transport.start_link(mod: TestApp, width: 0, height: 6, target: self())
      end

      assert_raise ArgumentError, ~r/positive integers/, fn ->
        Transport.start_link(mod: TestApp, width: 10, height: -1, target: self())
      end
    end

    test "raises ArgumentError when target is not a pid" do
      assert_raise ArgumentError, ~r/:target as pid/, fn ->
        Transport.start_link(mod: TestApp, width: 10, height: 2, target: :not_a_pid)
      end
    end

    @tag capture_log: true
    test "propagates {:error, _} from a failing mount/1 and closes the CellSession" do
      # When mod.mount/1 returns {:error, _}, ExRatatui.Server's
      # `continue_init_cell_session` closes the CellSession and returns
      # {:stop, reason} from init/1. The trap_exit dance below is
      # required because GenServer.start_link links the Server to us
      # before init runs: when the Server dies, the EXIT signal hits
      # the test process. With trap_exit set, `proc_lib:start_link`'s
      # internal receive consumes that EXIT and converts it to a
      # {:error, reason} return value — the test's mailbox stays
      # clean. Without trap_exit, the test process would die. (The
      # error log noise in capture_log comes from the internal
      # Task.Supervisor that the Server started in init/1, which gets
      # its own EXIT because it was linked to the dying Server.)
      Process.flag(:trap_exit, true)

      assert {:error, :mount_failed} =
               Transport.start_link(
                 mod: FailingMountApp,
                 width: 10,
                 height: 2,
                 target: self()
               )

      # proc_lib:start_link consumed the EXIT internally — mailbox is clean.
      refute_receive {:EXIT, _, _}, 50
    end
  end

  describe "push_event/2" do
    test "delivers an event to the App via the server mailbox" do
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 1,
          target: self(),
          test_pid: self()
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, _initial}, 1000

      key = %Key{code: "a", modifiers: [], kind: "press"}
      :ok = Transport.push_event(refs, key)

      # The App saw the event and the runtime followed it with a render
      # that shipped a non-empty diff (counter went 0 → 1).
      assert_receive {:event, ^key}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, %Diff{ops: [_]}}, 1000

      Transport.stop(refs)
    end

    test "accepts a bare server pid as a shortcut" do
      # `push_event/2` should work with either the full refs map (which
      # the LiveView already has in its assigns) or just the server
      # pid — the latter saves an unnecessary destructure in callsites
      # that only need to forward an event.
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 1,
          target: self(),
          test_pid: self()
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, _}, 1000

      key = %Key{code: "x", modifiers: [], kind: "press"}
      :ok = Transport.push_event(refs.server, key)

      assert_receive {:event, ^key}, 1000

      Transport.stop(refs)
    end
  end

  describe "resize/3" do
    test "resizes the CellSession and triggers a full-grid follow-up render" do
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 2,
          target: self(),
          test_pid: self()
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, %Diff{width: 10, height: 2}}, 1000

      :ok = Transport.resize(refs, 20, 4)

      # The App receives a Resize event in handle_event/2 and the
      # follow-up render emits a FULL diff at the new dimensions —
      # CellSession's documented behaviour after a resize.
      assert_receive {:event, %ExRatatui.Event.Resize{width: 20, height: 4}}, 1000

      assert_receive {:phoenix_ex_ratatui, :render, %Diff{width: 20, height: 4, ops: ops}},
                     1000

      assert length(ops) == 20 * 4

      Transport.stop(refs)
    end

    test "returns {:error, _} when the underlying session is already closed" do
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 2,
          target: self(),
          test_pid: self()
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, _}, 1000

      :ok = CellSession.close(refs.cell_session)

      assert {:error, reason} = Transport.resize(refs, 20, 4)
      assert reason =~ "closed"

      # The server isn't notified of the resize, so it should not have
      # received an :ex_ratatui_resize on its mailbox via this call.
      # We verify by absence: no follow-up render with new dimensions.
      refute_receive {:phoenix_ex_ratatui, :render, %Diff{width: 20}}, 100

      Transport.stop(refs)
    end
  end

  describe "stop/2" do
    test "stops the server and closes the CellSession" do
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 2,
          target: self(),
          test_pid: self()
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, _}, 1000

      :ok = Transport.stop(refs)

      # terminate/2 ran on the App — the test_pid receives the exit reason.
      assert_receive {:terminated, :normal}, 1000

      # CellSession.close ran via the server's terminate clause —
      # subsequent draws on the session error with "closed".
      refute Process.alive?(refs.server)
      assert {:error, reason} = CellSession.draw(refs.cell_session, [])
      assert reason =~ "closed"
    end

    test "is a no-op when the server is already dead" do
      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 10,
          height: 2,
          target: self(),
          test_pid: self()
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, _}, 1000

      :ok = GenServer.stop(refs.server)
      refute Process.alive?(refs.server)

      # Calling stop/2 again on the dead refs should not raise.
      assert :ok = Transport.stop(refs)
    end
  end

  describe "linked lifecycle" do
    @tag capture_log: true
    test "server exits when the calling process dies" do
      # The whole point of linking through start_link/1: when the LV
      # process exits (browser disconnect, navigation, crash), the
      # server's terminate/2 runs deterministically and closes the
      # session. We verify by spawning a parent that starts the
      # transport, then killing the parent and watching the server.
      test_pid = self()

      parent =
        spawn(fn ->
          {:ok, refs} =
            Transport.start_link(
              mod: TestApp,
              width: 10,
              height: 2,
              target: test_pid,
              test_pid: test_pid
            )

          send(test_pid, {:refs, refs})
          # Stay alive until we're killed.
          Process.sleep(:infinity)
        end)

      assert_receive {:refs, refs}, 1000
      assert_receive {:mounted, _}, 1000
      assert_receive {:phoenix_ex_ratatui, :render, _}, 1000

      ref = Process.monitor(refs.server)
      Process.exit(parent, :kill)

      # The server died because of the link — same EXIT propagation
      # SSH and Distributed transports rely on. We don't see
      # `terminated` here because the kill bypasses orderly shutdown.
      assert_receive {:DOWN, ^ref, :process, _, _}, 1000
      refute Process.alive?(refs.server)
    end
  end
end

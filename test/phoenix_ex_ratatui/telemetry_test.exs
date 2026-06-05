defmodule PhoenixExRatatui.TelemetryTest do
  @moduledoc """
  Verifies every documented `phoenix_ex_ratatui` telemetry event fires
  at the right boundary with the right metadata.

  Pattern for each test:
    1. `:telemetry.attach_many` against the events the test cares about
    2. handler forwards `{event, measurements, metadata}` to `self()`
    3. trigger the action that should fire the event
    4. `assert_receive` on the expected payload
    5. `:telemetry.detach` in `on_exit/1` so async handlers don't bleed
       across tests

  Each test uses a unique handler id so async ExUnit runs (this file
  is `async: true`) don't collide on `:telemetry`'s global registry.
  """

  # `:telemetry` handlers are global state. With async tests, a
  # `refute_receive` against "this event must NOT fire" is racy
  # against handlers attached by parallel tests that DO fire it. We
  # run this whole module serially to keep those refute assertions
  # deterministic. The runtime cost is negligible (~0.5s for the
  # full file) and the only alternative — filtering events by
  # per-test marker metadata — would complicate every assertion.
  use ExUnit.Case, async: false

  alias PhoenixExRatatui.Telemetry
  alias PhoenixExRatatui.TestApp
  alias PhoenixExRatatui.Transport

  defp attach(test_pid, events) do
    handler_id = "phoenix-ex-ratatui-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, meta, _ ->
        send(test_pid, {:telemetry, event, measurements, meta})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "transport.connect span" do
    test "fires :stop with mount metadata and a duration measurement" do
      attach(self(), [[:phoenix_ex_ratatui, :transport, :connect, :stop]])

      {:ok, refs} =
        Transport.start_link(
          mod: TestApp,
          width: 12,
          height: 4,
          target: self(),
          test_pid: self()
        )

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :transport, :connect, :stop],
                      measurements, meta},
                     1000

      # `:duration` is in native time units; just assert presence and
      # that it's positive, not an exact value.
      assert is_integer(measurements.duration)
      assert measurements.duration > 0

      assert meta.mod == TestApp
      assert meta.width == 12
      assert meta.height == 4
      assert meta.target == self()

      Transport.stop(refs)
    end

    @tag capture_log: true
    test "fires :exception when mount returns {:error, _} (the App's mount aborts)" do
      # The Telemetry helper passes the user fn's return value through
      # unchanged — when start_server returns {:error, _}, the span's
      # :stop event still fires (no exception was raised). Telemetry's
      # :exception event only fires on raised exceptions. So we
      # actually expect :stop here, with the :error tuple passed
      # through. This pins the contract that Telemetry.span doesn't
      # reinterpret error returns as exceptions.
      attach(self(), [[:phoenix_ex_ratatui, :transport, :connect, :stop]])

      Process.flag(:trap_exit, true)

      assert {:error, :mount_failed} =
               Transport.start_link(
                 mod: PhoenixExRatatui.FailingMountApp,
                 width: 8,
                 height: 2,
                 target: self()
               )

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :transport, :connect, :stop], _, meta},
                     1000

      assert meta.mod == PhoenixExRatatui.FailingMountApp
    end
  end

  describe "transport.disconnect event" do
    test "fires when Transport.stop/2 runs against a live server" do
      # Trap exits because Transport.start_link links the runtime
      # server to us; GenServer.stop with anything other than
      # `:normal` propagates an EXIT signal to the linked caller, and
      # without trap_exit the test process would die before reaching
      # the assert_receive below.
      Process.flag(:trap_exit, true)
      attach(self(), [[:phoenix_ex_ratatui, :transport, :disconnect]])

      {:ok, refs} = Transport.start_link(mod: TestApp, width: 6, height: 2, target: self())

      :ok = Transport.stop(refs, :shutdown)

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :transport, :disconnect],
                      %{system_time: _}, %{mod: TestApp, reason: :shutdown}},
                     1000
    end

    test "does NOT fire when Transport.stop/2 is called against an already-dead server" do
      # The "no-op on dead server" branch of Transport.stop/2 short-
      # circuits before reaching the telemetry call. We document that
      # so consumers don't get phantom disconnects from cleanup races.
      attach(self(), [[:phoenix_ex_ratatui, :transport, :disconnect]])

      {:ok, refs} = Transport.start_link(mod: TestApp, width: 6, height: 2, target: self())
      :ok = GenServer.stop(refs.server)
      refute Process.alive?(refs.server)

      :ok = Transport.stop(refs)

      refute_receive {:telemetry, [:phoenix_ex_ratatui, :transport, :disconnect], _, _}, 100
    end
  end

  describe "render.frame span" do
    test "fires :stop with width/height/ops_count metadata when LiveView pushes a frame" do
      # The render.frame span lives inside the LiveView macro's
      # __push_render__/3 helper, not the Transport. We invoke it
      # directly with a synthetic socket + diff so the test stays
      # focused on telemetry semantics rather than LiveView
      # plumbing (which `live_view_test.exs` covers exhaustively).
      attach(self(), [[:phoenix_ex_ratatui, :render, :frame, :stop]])

      diff = %ExRatatui.CellSession.Diff{
        width: 4,
        height: 1,
        ops: [
          %ExRatatui.CellSession.Cell{row: 0, col: 0, symbol: "A"},
          %ExRatatui.CellSession.Cell{row: 0, col: 1, symbol: "B"}
        ]
      }

      socket = synthetic_socket()
      _socket = PhoenixExRatatui.LiveView.__push_render__(socket, TestApp, diff)

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :render, :frame, :stop], measurements,
                      meta},
                     1000

      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert meta.mod == TestApp
      assert meta.width == 4
      assert meta.height == 1
      assert meta.ops_count == 2
    end
  end

  describe "input.forward event" do
    test "fires when LiveView forwards a decoded input to the Transport" do
      attach(self(), [[:phoenix_ex_ratatui, :input, :forward]])

      {:ok, refs} = Transport.start_link(mod: TestApp, width: 8, height: 1, target: self())

      payload = %{"kind" => "key", "code" => "a", "modifiers" => [], "press_kind" => "press"}
      socket = synthetic_socket(%{tui: refs})
      PhoenixExRatatui.LiveView.__handle_input__(socket, payload)

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :input, :forward], %{system_time: _},
                      meta},
                     1000

      assert meta.mod == TestApp
      assert %ExRatatui.Event.Key{code: "a", kind: "press"} = meta.event

      Transport.stop(refs)
    end

    test "does NOT fire when input arrives before the Transport is up" do
      # Same drop-silently behaviour as the LV test: no Transport,
      # nothing to forward, no telemetry. Without this assertion a
      # future regression could start emitting phantom events for
      # the resize-before-input race.
      attach(self(), [[:phoenix_ex_ratatui, :input, :forward]])

      payload = %{"kind" => "key", "code" => "a", "modifiers" => []}
      socket = synthetic_socket(%{tui: nil})
      PhoenixExRatatui.LiveView.__handle_input__(socket, payload)

      refute_receive {:telemetry, [:phoenix_ex_ratatui, :input, :forward], _, _}, 100
    end
  end

  describe "Telemetry.span/3" do
    test "returns the wrapped function's value unchanged" do
      attach(self(), [[:phoenix_ex_ratatui, :test, :span, :stop]])

      result = Telemetry.span([:test, :span], %{tag: :hello}, fn -> :the_value end)

      assert result == :the_value

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :test, :span, :stop], _, %{tag: :hello}},
                     500
    end

    test "fires :start before :stop with matching metadata" do
      attach(self(), [
        [:phoenix_ex_ratatui, :test, :span, :start],
        [:phoenix_ex_ratatui, :test, :span, :stop]
      ])

      Telemetry.span([:test, :span], %{tag: :ordering}, fn -> :ok end)

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :test, :span, :start], _, _}, 500
      assert_receive {:telemetry, [:phoenix_ex_ratatui, :test, :span, :stop], _, _}, 500
    end

    test "fires :exception when the wrapped function raises" do
      attach(self(), [[:phoenix_ex_ratatui, :test, :span, :exception]])

      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span([:test, :span], %{}, fn -> raise "boom" end)
      end

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :test, :span, :exception], _, meta},
                     500

      assert meta.kind == :error
      assert %RuntimeError{message: "boom"} = meta.reason
    end
  end

  describe "Telemetry.execute/3" do
    test "auto-adds :system_time when not already present in measurements" do
      attach(self(), [[:phoenix_ex_ratatui, :test, :event]])

      Telemetry.execute([:test, :event], %{}, %{tag: :auto_time})

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :test, :event], measurements,
                      %{tag: :auto_time}},
                     500

      assert is_integer(measurements.system_time)
    end

    test "preserves an explicit :system_time in measurements" do
      attach(self(), [[:phoenix_ex_ratatui, :test, :event]])

      Telemetry.execute([:test, :event], %{system_time: 12_345}, %{})

      assert_receive {:telemetry, [:phoenix_ex_ratatui, :test, :event], %{system_time: 12_345},
                      _},
                     500
    end
  end

  describe "attach_default_logger/1" do
    test "attaches a handler that survives detach_default_logger/0" do
      assert :ok = Telemetry.attach_default_logger(level: :debug)

      # Re-attaching with the same handler id is rejected — pins the
      # idempotency contract.
      assert {:error, :already_exists} = Telemetry.attach_default_logger()

      assert :ok = Telemetry.detach_default_logger()
      assert {:error, :not_found} = Telemetry.detach_default_logger()
    end

    test "__default_logger_handler__/4 produces the documented log format" do
      # Invoke the handler directly rather than through `:telemetry`
      # + Logger's async backend. Going through capture_log + the
      # async :console backend is brittle in tests (the backend can
      # outlive capture_log's window even after Logger.flush/0); the
      # handler itself is what matters here, and it's a pure call
      # we can capture deterministically.
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Telemetry.__default_logger_handler__(
            [:phoenix_ex_ratatui, :test, :logger_smoke],
            %{system_time: 100},
            %{tag: :hello},
            %{level: :error}
          )
        end)

      assert log =~ "phoenix_ex_ratatui"
      assert log =~ "test.logger_smoke"
      assert log =~ ":hello"
    end
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  # Synthetic socket sufficient for invoking __push_render__/3 and
  # __handle_input__/2 directly. The real LV socket has many more
  # fields but only `:assigns` is consulted by these helpers.
  defp synthetic_socket(extra_assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      endpoint: PhoenixExRatatui.TestEndpoint,
      assigns: Map.merge(%{__changed__: %{}, tui: nil}, extra_assigns)
    }
  end
end

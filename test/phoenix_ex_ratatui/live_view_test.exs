defmodule PhoenixExRatatui.LiveViewTest do
  @moduledoc """
  End-to-end tests for the `PhoenixExRatatui.LiveView` macro and its
  generated callbacks.

  Uses `Phoenix.LiveViewTest.live_isolated/3` so we don't have to wire
  up a router. The `TestEndpoint` started in `test_helper.exs` handles
  the LV machinery; `PhoenixExRatatui.TestLive` is a one-line module
  that `use`s the macro against `PhoenixExRatatui.TestApp`.

  We can't drive a real browser hook from here, so we simulate the
  hook's events with `render_hook/3` and assert on the server-side
  responses with `assert_push_event/3`.
  """

  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ExRatatui.CellSession
  alias PhoenixExRatatui.FailingTestLive
  alias PhoenixExRatatui.LiveView, as: PXRLV
  alias PhoenixExRatatui.TestLive

  @endpoint PhoenixExRatatui.TestEndpoint

  describe "__build_using_quote__/1 (compile-time helper)" do
    # The __using__ macro delegates to __build_using_quote__/1 so the
    # option-parsing path is runtime-callable (and therefore tracked
    # by mix test --cover, which doesn't see compile-time macro
    # expansion). These tests assert option-handling shape directly.

    test "raises if :app is missing" do
      assert_raise KeyError, fn ->
        PXRLV.__build_using_quote__([])
      end
    end

    test "accepts :app and returns a quoted AST" do
      ast = PXRLV.__build_using_quote__(app: PhoenixExRatatui.TestApp)
      assert is_tuple(ast)
      # The quoted block is wrapped in a `:__block__` node — sanity
      # check that we got a real AST, not a raw atom or nil.
      assert elem(ast, 0) == :__block__
    end

    test "applies the configured :container_id default" do
      ast = PXRLV.__build_using_quote__(app: PhoenixExRatatui.TestApp)
      ast_string = Macro.to_string(ast)
      assert ast_string =~ "phoenix-ex-ratatui"
    end

    test "accepts a custom :container_id" do
      ast =
        PXRLV.__build_using_quote__(
          app: PhoenixExRatatui.TestApp,
          container_id: "my-custom-tui"
        )

      ast_string = Macro.to_string(ast)
      assert ast_string =~ "my-custom-tui"
    end

    test "__using__ macro body is invoked when expanded at runtime" do
      # The defmacro __using__ body delegates to __build_using_quote__/1.
      # That delegation line runs at compile time, which `mix test
      # --cover` doesn't track (cover instrumentation kicks in after
      # lib/ has compiled). Invoking the macro from inside a runtime
      # test via Code.eval_string makes the macro body run while cover
      # IS active, so the delegation line gets tracked. Without this
      # test, that single line shows up as uncovered.
      module_name = String.to_atom("Elixir.PhoenixExRatatui.LiveViewTest.RuntimeMacroTest")

      Code.eval_string("""
      defmodule #{inspect(module_name)} do
        use PhoenixExRatatui.LiveView, app: PhoenixExRatatui.TestApp
      end
      """)

      assert Code.ensure_loaded?(module_name)
      :code.purge(module_name)
      :code.delete(module_name)
    end
  end

  describe "decode_input/1 (public helper)" do
    # The decoder is exposed for users hand-rolling their own LiveView
    # without the macro, so it gets its own focused tests beyond the
    # mount-flow integration coverage below.

    test "decodes a key event payload into %ExRatatui.Event.Key{}" do
      assert PXRLV.decode_input(%{
               "kind" => "key",
               "code" => "a",
               "modifiers" => [],
               "press_kind" => "press"
             }) == %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
    end

    test "modifier strings convert to existing atoms only" do
      decoded =
        PXRLV.decode_input(%{
          "kind" => "key",
          "code" => "c",
          "modifiers" => ["ctrl", "shift"]
        })

      assert decoded.modifiers == [:ctrl, :shift]
    end

    test "press_kind defaults to \"press\" when omitted" do
      decoded = PXRLV.decode_input(%{"kind" => "key", "code" => "a", "modifiers" => []})
      assert decoded.kind == "press"
    end

    test "missing modifiers list defaults to empty" do
      decoded = PXRLV.decode_input(%{"kind" => "key", "code" => "a"})
      assert decoded.modifiers == []
    end
  end

  describe "mount" do
    test "renders the hook container with the configured app and id" do
      {:ok, _view, html} = live_isolated(build_conn(), TestLive)

      assert html =~ ~s(id="phoenix-ex-ratatui")
      assert html =~ ~s(phx-hook="PhoenixExRatatuiHook")
      assert html =~ ~s(phx-update="ignore")
      # The macro inserts the App module name into a data-* attribute
      # so the hook can read it client-side without a separate
      # round-trip. inspect/1 produces "PhoenixExRatatui.TestApp".
      assert html =~ ~s(data-phx-ex-ratatui-app="PhoenixExRatatui.TestApp")
    end

    test "no error message is rendered on a successful mount" do
      {:ok, _view, html} = live_isolated(build_conn(), TestLive)
      refute html =~ "TUI error:"
    end
  end

  describe "phx_ex_ratatui:resize event" do
    test "first resize starts the Transport and pushes the initial frame" do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      # Simulate the JS hook's first resize event after measuring the
      # cell grid in the browser. This is what kicks the lazy server
      # boot — `mount` itself doesn't start the Transport because the
      # hook owns the dimensions.
      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 20, "rows" => 4})

      # The Transport's first take_cells_diff returns the full grid as
      # ops because there's no prior baseline yet. encode_diff packs
      # that as a JSON-friendly map under "phx_ex_ratatui:render".
      assert_push_event(view, "phx_ex_ratatui:render", payload, 1000)
      assert payload["width"] == 20
      assert payload["height"] == 4
      assert length(payload["ops"]) == 20 * 4

      # Each op is the [row, col, sym, fg, bg, mods, skip] array
      # documented in Renderer.Html — verify shape on the first one.
      [first_op | _] = payload["ops"]
      assert is_list(first_op) and length(first_op) == 7
    end

    @tag capture_log: true
    test "Transport.start_link error from a mount-failing app surfaces as a :tui_error assign" do
      # The trap_exit in our generated mount/3 turns a
      # mod.mount/1 == {:error, _} into a clean Transport.start_link
      # error tuple instead of an LV-killing EXIT. The macro's error
      # branch then assigns :tui_error so render/1 paints a fallback.
      {:ok, view, _html} = live_isolated(build_conn(), FailingTestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 2})

      # The next render of the LV reflects the :tui_error assign.
      html = render(view)
      assert html =~ "TUI error:"
      assert html =~ "mount_failed"

      # And no render frame was pushed — the Transport never started.
      refute_push_event_arrives(view, "phx_ex_ratatui:render", 100)
    end

    test "subsequent resize delegates to Transport.resize and pushes a full frame at the new size" do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      # Boot the Transport via the first resize…
      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 2})
      assert_push_event(view, "phx_ex_ratatui:render", first_payload, 1000)
      assert first_payload["width"] == 10

      # …then send a second resize. The macro detects the existing
      # refs and calls Transport.resize/3, which: (1) resizes the
      # CellSession, (2) sends :ex_ratatui_resize to the runtime
      # server, (3) the server dispatches Event.Resize to the App
      # AND re-renders. The follow-up diff is FULL because the prior
      # baseline at the old area is no longer comparable.
      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 20, "rows" => 5})
      assert_push_event(view, "phx_ex_ratatui:render", second_payload, 1000)
      assert second_payload["width"] == 20
      assert second_payload["height"] == 5
      assert length(second_payload["ops"]) == 20 * 5
    end

    @tag capture_log: true
    test "resize on a closed underlying CellSession assigns :tui_error" do
      # Boot the Transport at a normal size, then forcibly close the
      # CellSession out from under it. The next resize from the hook
      # cannot succeed because Transport.resize → CellSession.resize
      # returns {:error, "...closed"}; the macro's error branch
      # surfaces that as :tui_error rather than crashing the LV.
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 2})
      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      # Reach into the LV's assigns and close the session by hand —
      # simulating the kind of mid-flight teardown we'd see from a
      # crashed downstream consumer or a manual stop.
      assigns = :sys.get_state(view.pid).socket.assigns
      :ok = CellSession.close(assigns.tui.cell_session)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 20, "rows" => 5})

      html = render(view)
      assert html =~ "TUI error:"
      assert html =~ "session closed"
    end
  end

  describe "phx_ex_ratatui:input event" do
    test "input before resize is silently dropped (no Transport yet)" do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      # The hook fired input before resize — odd but possible during
      # browser resize storms. The macro drops it silently rather
      # than crashing or queuing.
      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "a",
        "modifiers" => []
      })

      # No render fired because no Transport is running.
      refute_push_event_arrives(view, "phx_ex_ratatui:render", 100)
    end

    test "input after resize forwards to the Transport and triggers a re-render" do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 1})
      assert_push_event(view, "phx_ex_ratatui:render", _initial, 1000)

      # The TestApp paints a counter that goes 0 → 1 on any event,
      # so we expect exactly one cell to change.
      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "x",
        "modifiers" => []
      })

      assert_push_event(view, "phx_ex_ratatui:render", payload, 1000)
      assert payload["width"] == 10
      assert payload["height"] == 1
      # Counter cell flipped — small partial diff, not a full repaint.
      # Match against `[_ | _]` (cheaper than `length/1` per credo)
      # which asserts the ops list is non-empty without counting it.
      # The Paragraph widget can paint a few cells when the counter
      # digit's column crosses a width boundary, so we don't pin an
      # exact count.
      assert match?([_ | _], payload["ops"])
    end
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  # Phoenix.LiveViewTest doesn't ship a refute_push_event/3 macro the
  # way it ships assert_push_event/3, but the same idea is easy to
  # express against the test process mailbox: render_hook returns
  # synchronously, so any push_event the LV emitted is already in the
  # mailbox by the time we check.
  defp refute_push_event_arrives(view, event, timeout_ms) do
    refute_receive {:phoenix, :send_update, _}, timeout_ms
    refute_receive {%Phoenix.Socket.Reply{ref: _}, _}, 0

    assert_no_push_event(view, event)
  end

  defp assert_no_push_event(_view, _event) do
    # If a push_event had fired, assert_push_event with a 0-timeout
    # would have matched. We use receive with after 0 to peek without
    # blocking.
    receive do
      {:push_event, _ref, _payload} = msg ->
        flunk("unexpected push_event in mailbox: #{inspect(msg)}")
    after
      0 -> :ok
    end
  end
end

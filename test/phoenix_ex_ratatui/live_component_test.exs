defmodule PhoenixExRatatui.LiveComponentTest do
  @moduledoc """
  End-to-end tests for `PhoenixExRatatui.LiveComponent` embedded
  inside a parent LiveView.

  We mount `PhoenixExRatatui.TestParentLive` with `live_isolated/3`
  (no router needed), which renders `PhoenixExRatatui.TestComponent`
  — a unified-module fixture using the macro. We drive the
  component's hook events with `render_hook/3`. The test parent LV
  renders a heading sibling so we can verify the LiveComponent
  doesn't clobber unrelated content in the page.
  """

  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ExRatatui.CellSession
  alias PhoenixExRatatui.FailingTestComponent
  alias PhoenixExRatatui.LiveComponent, as: PXRLC
  alias PhoenixExRatatui.TestComponent
  alias PhoenixExRatatui.TestParentLive

  @endpoint PhoenixExRatatui.TestEndpoint

  describe "__build_using_quote__/0 (compile-time helper)" do
    test "returns a quoted AST" do
      ast = PXRLC.__build_using_quote__([])
      assert is_tuple(ast)
      assert elem(ast, 0) == :__block__
    end

    test "__using__ macro body is invoked when expanded at runtime" do
      module_name = String.to_atom("Elixir.PhoenixExRatatui.LiveComponentTest.RuntimeMacroTest")

      Code.eval_string("""
      defmodule #{inspect(module_name)} do
        use PhoenixExRatatui.LiveComponent
      end
      """)

      assert Code.ensure_loaded?(module_name)
      runtime = Module.concat(module_name, "Runtime")
      assert Code.ensure_loaded?(runtime)
      assert function_exported?(runtime, :mount, 1)

      :code.purge(runtime)
      :code.delete(runtime)
      :code.purge(module_name)
      :code.delete(module_name)
    end
  end

  describe "TestComponent module identity" do
    test "the unified-module is registered as a Phoenix LiveComponent" do
      # `use Phoenix.LiveComponent` (injected by our macro) injects
      # `__live__/0` returning component metadata — sanity-check the
      # generated TestComponent so a future accidental swap to
      # `Phoenix.LiveView` (and the resulting full-page behaviour
      # mismatch) breaks loudly in tests.
      live = TestComponent.__live__()
      assert live.kind == :component
      assert live.layout == false
    end

    test "TestComponent.Runtime delegates to the user module's tui_* callbacks" do
      assert TestComponent.Runtime.mount([]) == {:ok, %{n: 0}}

      frame = %ExRatatui.Frame{width: 10, height: 1}
      assert [{_widget, _rect}] = TestComponent.Runtime.render(%{n: 0}, frame)

      assert TestComponent.Runtime.handle_event(%ExRatatui.Event.Key{code: "x"}, %{n: 0}) ==
               {:noreply, %{n: 1}}

      assert TestComponent.Runtime.handle_event(%ExRatatui.Event.Key{code: "q"}, %{n: 0}) ==
               {:stop, %{n: 0}}
    end
  end

  describe "mount" do
    test "renders the LiveComponent's hook container alongside the parent's content" do
      {:ok, _view, html} = live_isolated(build_conn(), TestParentLive)

      assert html =~ ~s(id="parent-heading")
      assert html =~ ~s(id="embedded-tui")
      assert html =~ ~s(phx-hook="PhoenixExRatatuiHook")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(data-phx-ex-ratatui-runtime="PhoenixExRatatui.TestComponent.Runtime")
    end

    test "no error message renders for a healthy mount" do
      {:ok, _view, html} = live_isolated(build_conn(), TestParentLive)
      refute html =~ "TUI error:"
    end
  end

  describe "phx_ex_ratatui:resize event" do
    test "first resize boots the Transport and pushes the initial frame as a render event" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 16, "rows" => 3})

      assert_push_event(view, "phx_ex_ratatui:render", payload, 1000)
      assert payload["width"] == 16
      assert payload["height"] == 3
      assert length(payload["ops"]) == 16 * 3
    end

    test "subsequent resize delegates through Transport.resize and produces a full frame at the new size" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 2})

      assert_push_event(view, "phx_ex_ratatui:render", first, 1000)
      assert first["width"] == 8

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 14, "rows" => 4})

      assert_push_event(view, "phx_ex_ratatui:render", second, 1000)
      assert second["width"] == 14
      assert second["height"] == 4
      assert length(second["ops"]) == 14 * 4
    end

    @tag capture_log: true
    test "Transport.start_link error from a mount-failing app surfaces as :tui_error" do
      session = %{"component" => FailingTestComponent}
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive, session: session)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 2})

      html = render(view)
      assert html =~ "TUI error:"
      assert html =~ "mount_failed"
    end
  end

  describe "phx_ex_ratatui:input event" do
    test "input before the first resize is silently dropped" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "a",
        "modifiers" => []
      })

      refute_push_event(view, "phx_ex_ratatui:render", 100)
    end

    test "input after resize forwards through the Transport and triggers a re-render" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 1})

      assert_push_event(view, "phx_ex_ratatui:render", _initial, 1000)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "x",
        "modifiers" => []
      })

      assert_push_event(view, "phx_ex_ratatui:render", payload, 1000)
      assert match?([_ | _], payload["ops"])
    end
  end

  describe "send_update wiring (the LC-specific bit)" do
    test "diffs from the runtime arrive through update/2 (not handle_info)" do
      # This is the property that distinguishes the LC from the
      # full-page LiveView. There's no handle_info on a LiveComponent;
      # the writer in __start_transport__ calls send_update, which
      # routes the diff through update(%{tui_diff: _}, socket) —
      # which then calls push_event from there. If a future
      # refactor accidentally swaps in a `send/2`-based writer, the
      # LV would never see the diff and the next render assertion
      # below would time out.
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 4, "rows" => 1})

      assert_push_event(view, "phx_ex_ratatui:render", payload, 1000)
      assert payload["width"] == 4
      assert payload["height"] == 1
    end
  end

  describe "session lifecycle when underlying CellSession is closed" do
    @tag capture_log: true
    test "resize on a closed session assigns :tui_error" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 2})

      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      lc_assigns = component_assigns(view, "embedded-tui")
      :ok = CellSession.close(lc_assigns.tui.cell_session)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 2})

      html = render(view)
      assert html =~ "TUI error:"
      assert html =~ "session closed"
    end
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  # No public API to read a LiveComponent's assigns at runtime, so we
  # peek at the LV's component registry via :sys.get_state. Brittle
  # but acceptable for a single internal-state assertion.
  defp component_assigns(view, id) do
    state = :sys.get_state(view.pid)

    state.components
    |> elem(0)
    |> Enum.find_value(fn
      {_cid, {_module, ^id, assigns, _, _}} -> assigns
      _ -> nil
    end)
  end
end

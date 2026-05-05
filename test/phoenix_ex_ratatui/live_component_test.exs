defmodule PhoenixExRatatui.LiveComponentTest do
  @moduledoc """
  End-to-end tests for `PhoenixExRatatui.LiveComponent` embedded
  inside a parent LiveView.

  We mount `PhoenixExRatatui.TestParentLive` with `live_isolated/3`
  (no router needed) and drive the component's hook events with
  `render_hook/3`. The test parent LV renders a heading sibling so
  we can verify the LiveComponent doesn't clobber unrelated content
  in the page.
  """

  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ExRatatui.CellSession
  alias PhoenixExRatatui.FailingMountApp
  alias PhoenixExRatatui.TestParentLive

  @endpoint PhoenixExRatatui.TestEndpoint

  describe "module identity" do
    test "is registered as a Phoenix LiveComponent" do
      # `use Phoenix.LiveComponent` injects `__live__/0` returning
      # component metadata — we sanity-check it here so a future
      # accidental swap to `Phoenix.LiveView` (and the resulting
      # full-page behaviour mismatch) breaks loudly in tests.
      live = PhoenixExRatatui.LiveComponent.__live__()
      assert live.kind == :component
      assert live.layout == false
    end
  end

  describe "mount" do
    test "renders the LiveComponent's hook container alongside the parent's content" do
      {:ok, _view, html} = live_isolated(build_conn(), TestParentLive)

      # Both the parent's heading AND the LC's hook container render
      # in the same response. This is the headline difference vs the
      # full-page LiveView macro.
      assert html =~ ~s(id="parent-heading")
      assert html =~ ~s(id="embedded-tui")
      assert html =~ ~s(phx-hook="PhoenixExRatatuiHook")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(data-phx-ex-ratatui-app="PhoenixExRatatui.TestApp")
    end

    test "no error message renders for a healthy mount" do
      {:ok, _view, html} = live_isolated(build_conn(), TestParentLive)
      refute html =~ "TUI error:"
    end
  end

  describe "phx_ex_ratatui:resize event" do
    test "first resize boots the Transport and pushes the initial frame as a render event" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      # Target the LiveComponent specifically — the hook lives inside
      # the embedded-tui div, so element/3 narrows the render_hook
      # to that component (otherwise the parent LV would receive it).
      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 16, "rows" => 3})

      assert_push_event(view, "phx_ex_ratatui:render", payload, 1000)
      assert payload["width"] == 16
      assert payload["height"] == 3
      # First take_cells_diff after construction: full grid.
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
      # Resize invalidates the diff baseline, so the follow-up frame
      # is full at the new dimensions.
      assert length(second["ops"]) == 14 * 4
    end

    @tag capture_log: true
    test "Transport.start_link error from a mount-failing app surfaces as :tui_error" do
      session = %{"app" => FailingMountApp}
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

      # No render fires — Transport isn't up yet, nothing to forward.
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
      # Counter cell flipped — non-empty diff, but smaller than full.
      assert match?([_ | _], payload["ops"])
    end
  end

  describe "send_update wiring (the LC-specific bit)" do
    test "diffs from the runtime arrive through update/2 (not handle_info)" do
      # This is the property that distinguishes the LC from the
      # full-page LiveView. There's no handle_info on a LiveComponent;
      # the writer in start_transport/3 calls send_update, which
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

      # Reach into the LV state, find the LiveComponent's CellSession
      # via send_update reflection, and close it — then assert the
      # next resize attempt surfaces :tui_error.
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

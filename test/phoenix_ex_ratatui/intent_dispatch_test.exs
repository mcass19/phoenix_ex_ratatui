defmodule PhoenixExRatatui.IntentDispatchTest do
  @moduledoc """
  End-to-end tests for runtime intents flowing from a TUI app through
  `ExRatatui.Server`'s `intent_writer_fn` into Phoenix LV navigation
  primitives (`push_navigate` / `push_patch` / `redirect`).

  Both unified-module APIs are covered: the full-page LV and the
  embedded LC. Direct unit tests for `dispatch_intent/2` cover the
  shape branching without going through the full runtime.
  """

  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket
  alias PhoenixExRatatui.LiveView, as: PXRLV
  alias PhoenixExRatatui.TestLive
  alias PhoenixExRatatui.TestParentLive

  @endpoint PhoenixExRatatui.TestEndpoint

  describe "dispatch_intent/2 (public helper)" do
    # Direct unit tests against the dispatch table — independent of
    # the runtime path. Drives a bare Socket struct so we can assert
    # on the redirect/navigate fields the LV runtime sets.

    setup do
      socket = %Socket{
        endpoint: PhoenixExRatatui.TestEndpoint,
        router: PhoenixExRatatui.TestRouter,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:ok, socket: socket}
    end

    test "{:navigate, path} sets push_navigate redirect", %{socket: socket} do
      result = PXRLV.dispatch_intent(socket, {:navigate, "/dashboard"})
      assert result.redirected == {:live, :redirect, %{kind: :push, to: "/dashboard"}}
    end

    test "{:patch, path} sets push_patch redirect", %{socket: socket} do
      result = PXRLV.dispatch_intent(socket, {:patch, "/dashboard"})
      assert result.redirected == {:live, :patch, %{kind: :push, to: "/dashboard"}}
    end

    test "{:redirect, path} sets internal redirect", %{socket: socket} do
      result = PXRLV.dispatch_intent(socket, {:redirect, "/login"})
      assert result.redirected == {:redirect, %{to: "/login", status: 302}}
    end

    test "{:redirect, [external: url]} sets external redirect", %{socket: socket} do
      result = PXRLV.dispatch_intent(socket, {:redirect, [external: "https://example.com"]})
      assert result.redirected == {:redirect, %{external: "https://example.com", status: 302}}
    end

    @tag capture_log: true
    test "unrecognised intent shape is dropped silently", %{socket: socket} do
      result = PXRLV.dispatch_intent(socket, {:teleport, "/nowhere"})
      # Socket unchanged — the unrecognised intent is logged at warning
      # but no redirect is set, so the LV just keeps rendering.
      assert result.redirected == nil
    end
  end

  describe "LiveView intent flow" do
    test ":navigate intent from tui_handle_event triggers push_navigate", %{} do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 1})
      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      # Send a key that emits {:navigate, "/elsewhere"} from the TUI.
      # render_hook returns synchronously after the LV processes the
      # message, so the push_navigate has already been dispatched by
      # the time we assert.
      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "navigate",
        "modifiers" => []
      })

      assert_redirect(view, "/elsewhere")
    end

    # `push_patch` integration is covered by the dispatch_intent/2 unit
    # test. We don't repeat it here because `live_isolated/3` mounts
    # the LV outside a router, and Phoenix LV requires a router-mounted
    # LV to resolve the patched URI.

    test ":redirect intent triggers full redirect", %{} do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 1})
      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "redirect",
        "modifiers" => []
      })

      assert_redirect(view, "/login")
    end

    @tag capture_log: true
    test "unrecognised intent leaves the socket alive (logged, not crashed)", %{} do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 1})
      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      # Should NOT redirect, NOT crash. Just keep going.
      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "unknown_intent",
        "modifiers" => []
      })

      # The LV is still alive and rendering — a follow-up event still
      # produces a frame.
      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "x",
        "modifiers" => []
      })

      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)
    end
  end

  describe "LiveComponent intent flow" do
    test ":navigate intent from an embedded LC routes through send_update and triggers push_navigate" do
      {:ok, view, _html} = live_isolated(build_conn(), TestParentLive)

      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 1})

      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      # The intent_writer in the LC's start_transport path calls
      # send_update with %{tui_intent: intent}; the LC's update/2
      # then routes through dispatch_intent/2.
      view
      |> element("#embedded-tui")
      |> render_hook("phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "navigate",
        "modifiers" => []
      })

      assert_redirect(view, "/elsewhere")
    end
  end

  describe "telemetry" do
    setup do
      {:ok, _} = Application.ensure_all_started(:telemetry)

      handler_id = "intent-dispatch-test-#{System.unique_integer()}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:phoenix_ex_ratatui, :intent, :dispatch],
        fn _, measurements, meta, _ ->
          send(test_pid, {:telemetry_intent, measurements, meta})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "intent dispatch emits a telemetry event" do
      {:ok, view, _html} = live_isolated(build_conn(), TestLive)

      render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 8, "rows" => 1})
      assert_push_event(view, "phx_ex_ratatui:render", _, 1000)

      render_hook(view, "phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "navigate",
        "modifiers" => []
      })

      assert_receive {:telemetry_intent, %{system_time: _}, %{intent: {:navigate, "/elsewhere"}}}
      assert_redirect(view, "/elsewhere")
    end
  end
end

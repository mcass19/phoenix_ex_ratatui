defmodule PhoenixExRatatui.KeyReleasesTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ExRatatui.Event.Key
  alias PhoenixExRatatui.KeyLive

  @endpoint PhoenixExRatatui.TestEndpoint

  defp start(releases?) do
    session = %{"test_pid" => self(), "releases?" => releases?}
    {:ok, view, _html} = live_isolated(build_conn(), KeyLive, session: session)

    render_hook(view, "phx_ex_ratatui:resize", %{"cols" => 10, "rows" => 2})
    assert_push_event(view, "phx_ex_ratatui:render", _, 1000)
    view
  end

  defp key(view, press_kind) do
    payload = %{"kind" => "key", "code" => "up", "modifiers" => [], "press_kind" => press_kind}
    render_hook(view, "phx_ex_ratatui:input", payload)
  end

  test "an app that asked for releases gets press, repeat and release" do
    view = start(true)

    key(view, "press")
    key(view, "repeat")
    key(view, "release")

    assert_receive {:tui_event, %Key{code: "up", kind: "press"}}, 1000
    assert_receive {:tui_event, %Key{code: "up", kind: "repeat"}}, 1000
    assert_receive {:tui_event, %Key{code: "up", kind: "release"}}, 1000
  end

  test "an app that didn't sees a press-only terminal" do
    view = start(false)

    key(view, "press")
    key(view, "repeat")
    key(view, "release")

    assert_receive {:tui_event, %Key{code: "up", kind: "press"}}, 1000
    assert_receive {:tui_event, %Key{code: "up", kind: "press"}}, 1000
    refute_receive {:tui_event, %Key{kind: "release"}}, 100
  end
end

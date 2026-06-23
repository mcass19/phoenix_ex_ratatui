defmodule DemoWeb.ViewsRenderTest do
  @moduledoc """
  Smoke test that every demo view's `tui_render/2` output actually
  paints through a real `ExRatatui.CellSession` without raising — the
  end-to-end check that the widget structs each view builds are valid
  (this is what catches things like wrong Canvas bounds or bad widget
  fields, which compile fine but blow up at draw time).
  """
  use ExUnit.Case, async: true

  alias ExRatatui.CellSession
  alias ExRatatui.Event.Key
  alias ExRatatui.Event.Resize
  alias ExRatatui.Frame

  @width 80
  @height 24

  test "HomeLive paints the animated landing scene" do
    {:ok, state} = DemoWeb.HomeLive.tui_init([])

    {:noreply, state} =
      DemoWeb.HomeLive.tui_update({:event, %Resize{width: @width, height: @height}}, state)

    assert painted?(DemoWeb.HomeLive.tui_render(state, frame()))
  end

  test "ChatLive paints the chat interface" do
    {:ok, state} = DemoWeb.ChatLive.tui_mount([])
    assert painted?(DemoWeb.ChatLive.tui_render(state, frame()))
  end

  test "SystemMonitorPanel paints the system monitor" do
    {:ok, state} = DemoWeb.SystemMonitorPanel.tui_init([])
    assert painted?(DemoWeb.SystemMonitorPanel.tui_render(state, frame()))
  end

  test "CoexistenceLive paints the TUI box" do
    {:ok, state} = DemoWeb.CoexistenceLive.tui_mount([])
    assert painted?(DemoWeb.CoexistenceLive.tui_render(state, frame()))
  end

  test "ChatLive handles string-modifier keys without crashing" do
    # The LiveView hook delivers modifiers as strings (["shift"], ["ctrl"]).
    # A capital letter or a Shift/Ctrl press must not blow up the runtime.
    {:ok, state} = DemoWeb.ChatLive.tui_mount([])

    assert {:noreply, _} =
             DemoWeb.ChatLive.tui_handle_event(
               %Key{code: "A", modifiers: ["shift"], kind: "press"},
               state
             )

    assert {:noreply, _} =
             DemoWeb.ChatLive.tui_handle_event(
               %Key{code: "x", modifiers: ["ctrl"], kind: "press"},
               state
             )

    assert {:noreply, _} =
             DemoWeb.ChatLive.tui_handle_event(
               %Key{code: "enter", modifiers: ["shift"], kind: "press"},
               state
             )
  end

  defp frame, do: %Frame{width: @width, height: @height}

  defp painted?(widgets) do
    session = CellSession.new(@width, @height)
    :ok = CellSession.draw(session, widgets)
    %{cells: cells} = CellSession.take_cells(session)
    Enum.any?(cells, &(&1.symbol != " "))
  end
end

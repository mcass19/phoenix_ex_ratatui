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
  alias ExRatatui.CellSession.Region
  alias ExRatatui.Command
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

  test "CubeLive paints the cube as cells on a plain session" do
    {:ok, state, commands: [%Command{kind: :async}]} = DemoWeb.CubeLive.tui_init([])
    assert painted?(DemoWeb.CubeLive.tui_render(state, frame()))
  end

  test "CubeLive ships the cube and the photo as pixel regions on a font-size session" do
    state = cube_with_photo()

    session = CellSession.new(@width, @height, font_size: {8, 16})
    :ok = CellSession.draw(session, DemoWeb.CubeLive.tui_render(state, frame()))
    %{regions: regions} = CellSession.take_cells(session)

    assert [%Region{format: :rgb8}, %Region{format: :rgb8}] = regions

    # Toggling to cells keeps both inside the grid.
    {:noreply, cells_state} =
      DemoWeb.CubeLive.tui_update({:event, %Key{code: "m", kind: "press"}}, state)

    :ok = CellSession.draw(session, DemoWeb.CubeLive.tui_render(cells_state, frame()))
    assert %{regions: []} = CellSession.take_cells(session)
  end

  test "CubeLive shows the fetch error and fetches again on n" do
    {:ok, state, _opts} = DemoWeb.CubeLive.tui_init([])

    {:noreply, failed} =
      DemoWeb.CubeLive.tui_update({:info, {:photo, {:error, :nxdomain}}}, state)

    assert painted?(DemoWeb.CubeLive.tui_render(failed, frame()))

    assert {:noreply, %{photo_status: :loading}, commands: [%Command{kind: :async}]} =
             DemoWeb.CubeLive.tui_update({:event, %Key{code: "n", kind: "press"}}, failed)

    # A fetch already in flight is not started twice.
    assert {:noreply, ^state} =
             DemoWeb.CubeLive.tui_update({:event, %Key{code: "n", kind: "press"}}, state)
  end

  test "CubeLive reports a photo it cannot decode" do
    {:ok, state, _opts} = DemoWeb.CubeLive.tui_init([])

    assert {:noreply, %{photo: nil, photo_status: {:error, {:decode_failed, _}}}} =
             DemoWeb.CubeLive.tui_update({:info, {:photo, {:ok, "not an image"}}}, state)
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

  # A loaded /cube state, with a small generated PNG standing in for the
  # picsum.photos download.
  defp cube_with_photo do
    {:ok, state, _opts} = DemoWeb.CubeLive.tui_init([])

    png =
      Region.to_png(%Region{
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        pixel_width: 4,
        pixel_height: 4,
        format: :rgb8,
        data: :binary.copy(<<200, 80, 40>>, 16)
      })

    {:noreply, loaded} = DemoWeb.CubeLive.tui_update({:info, {:photo, {:ok, png}}}, state)
    loaded
  end

  defp painted?(widgets) do
    session = CellSession.new(@width, @height)
    :ok = CellSession.draw(session, widgets)
    %{cells: cells} = CellSession.take_cells(session)
    Enum.any?(cells, &(&1.symbol != " "))
  end
end

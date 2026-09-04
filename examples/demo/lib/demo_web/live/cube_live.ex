defmodule DemoWeb.CubeLive do
  @moduledoc """
  Pixel regions in the browser: a spinning `Viewport3D` cube.

  The JS hook reports the measured cell size with its resize event, the
  transport opens the `CellSession` as a pixel surface, and the viewport
  arrives as a PNG region that the hook paints as an `<img>` over the
  cell grid — crisp at the pane's real pixel size, not as half blocks.
  Press `m` to toggle between `:auto` (pixels) and `:braille` (cells)
  and see the difference; the rest of the frame is ordinary cells.

  Reducer runtime: a `Subscription.interval` turns the cube.
  """
  use PhoenixExRatatui.LiveView, runtime: :reducer

  alias Demo.UI
  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Subscription
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Viewport3D}

  @tick_ms 80
  @step 0.05

  def tui_init(_opts), do: {:ok, %{angle: 0.0, mode: :auto}}

  def tui_subscriptions(_state), do: [Subscription.interval(:spin, @tick_ms, :tick)]

  def tui_update({:info, :tick}, state), do: {:noreply, %{state | angle: state.angle + @step}}
  def tui_update({:info, _msg}, state), do: {:noreply, state}

  def tui_update({:event, %Key{code: "m"}}, state),
    do: {:noreply, %{state | mode: toggle(state.mode)}}

  def tui_update({:event, %Key{code: "h"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/"}]}

  def tui_update({:event, _event}, state), do: {:noreply, state}

  def tui_render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [content_area, footer_area] = UI.split_for_footer(area)

    viewport = %Viewport3D{
      scene: scene(state.angle),
      camera: %Camera{position: {2.6, 2.0, 3.4}, target: {0.0, 0.0, 0.0}},
      render_mode: state.mode,
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: Demo.Theme.border_style(),
        title: " cube — #{mode_label(state.mode)} "
      }
    }

    footer = UI.nav_hints([{"m", "toggle #{mode_label(toggle(state.mode))}"}, {"h", "home"}])

    [{viewport, content_area}, {footer, footer_area}]
  end

  defp toggle(:auto), do: :braille
  defp toggle(:braille), do: :auto

  defp mode_label(:auto), do: "pixels"
  defp mode_label(:braille), do: "cells"

  defp scene(angle) do
    %Scene{
      objects: [
        %Object{
          mesh: Mesh.cube(),
          material: %Material{color: {120, 170, 255}},
          transform: %Transform{rotation: {:euler_xyz, {0.5, angle, 0.0}}}
        }
      ],
      lights: [
        Light.ambient({255, 255, 255}, 0.25),
        Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255})
      ],
      background: {10, 10, 18}
    }
  end
end

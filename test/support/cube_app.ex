defmodule PhoenixExRatatui.CubeApp do
  @moduledoc """
  `ExRatatui.App` fixture that fills the frame with a pixel-mode
  `Viewport3D`, so tests can see pixel regions travel through the
  transport. Every event nudges the cube's rotation, which changes the
  region; a `"noop"` key re-renders without changing anything, which
  is the case where an unchanged region set must not be re-sent.
  """
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.ThreeD.{Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.Viewport3D

  @impl true
  def mount(opts) do
    test_pid = Keyword.get(opts, :test_pid)
    if test_pid, do: send(test_pid, {:mounted, opts})
    {:ok, %{test_pid: test_pid, angle: 0.0}}
  end

  @impl true
  def render(state, frame) do
    [{viewport(state.angle), %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  @impl true
  def handle_event(%Key{code: "noop"}, state), do: {:noreply, state}
  def handle_event(_event, state), do: {:noreply, %{state | angle: state.angle + 0.5}}

  @doc "The widget the fixture renders, shared with the LiveView fixture."
  def viewport(angle) do
    scene = %Scene{
      objects: [
        %Object{
          mesh: Mesh.cube(),
          material: %Material{color: {100, 150, 255}},
          transform: %Transform{rotation: {:euler_xyz, {0.4, angle, 0.0}}}
        }
      ],
      lights: [Light.ambient({255, 255, 255}, 0.3)]
    }

    %Viewport3D{scene: scene, render_mode: :auto}
  end
end

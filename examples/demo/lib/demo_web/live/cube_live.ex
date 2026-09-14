defmodule DemoWeb.CubeLive do
  @moduledoc """
  Pixel regions in the browser: a spinning `Viewport3D` cube next to a
  random photo from [picsum.photos](https://picsum.photos).

  The JS hook reports the measured cell size with its resize event, the
  transport opens the `CellSession` as a pixel surface, and both pixel
  widgets arrive as PNG regions that the hook paints as `<img>`s over the
  cell grid — crisp at the pane's real pixel size, not as half blocks.
  Press `m` to toggle both between pixels and cells (`:braille` for the
  cube, `:halfblocks` for the photo) and see the difference, and `n` for
  another photo; the rest of the frame is ordinary cells.

  Reducer runtime: a `Subscription.interval` turns the cube, and a
  `Command.async` fetches each photo off the runtime process.
  """
  use PhoenixExRatatui.LiveView, runtime: :reducer

  alias Demo.UI
  alias ExRatatui.Command
  alias ExRatatui.Event.Key
  alias ExRatatui.Image
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Subscription
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @tick_ms 80
  @step 0.05
  @background {10, 10, 18}
  @photo_url "https://picsum.photos/640/480"

  def tui_init(_opts) do
    state = %{angle: 0.0, mode: :auto, photo: nil, photo_status: :loading}
    {:ok, state, commands: [fetch_photo()]}
  end

  def tui_subscriptions(_state), do: [Subscription.interval(:spin, @tick_ms, :tick)]

  def tui_update({:info, :tick}, state), do: {:noreply, %{state | angle: state.angle + @step}}

  def tui_update({:info, {:photo, {:ok, bytes}}}, state) do
    case decode_photo(bytes) do
      {:ok, photo} -> {:noreply, %{state | photo: photo, photo_status: :ready}}
      {:error, reason} -> {:noreply, %{state | photo_status: {:error, reason}}}
    end
  end

  def tui_update({:info, {:photo, {:error, reason}}}, state),
    do: {:noreply, %{state | photo_status: {:error, reason}}}

  def tui_update({:info, _msg}, state), do: {:noreply, state}

  def tui_update({:event, %Key{code: "m"}}, state),
    do: {:noreply, %{state | mode: toggle(state.mode)}}

  def tui_update({:event, %Key{code: "n"}}, %{photo_status: :loading} = state),
    do: {:noreply, state}

  def tui_update({:event, %Key{code: "n"}}, state),
    do: {:noreply, %{state | photo_status: :loading}, commands: [fetch_photo()]}

  def tui_update({:event, %Key{code: "h"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/"}]}

  def tui_update({:event, _event}, state), do: {:noreply, state}

  def tui_render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [content_area, footer_area] = UI.split_for_footer(area)
    [cube_area, photo_area] = Layout.split(content_area, :horizontal, [{:fill, 1}, {:fill, 1}])

    viewport = %Viewport3D{
      scene: scene(state.angle),
      camera: %Camera{position: {2.6, 2.0, 3.4}, target: {0.0, 0.0, 0.0}},
      render_mode: cube_mode(state.mode),
      block: block(" cube — #{mode_label(state.mode)} ")
    }

    footer =
      UI.nav_hints([
        {"m", "toggle #{mode_label(toggle(state.mode))}"},
        {"n", "new photo"},
        {"h", "home"}
      ])

    [{viewport, cube_area}] ++ photo_pane(state, photo_area) ++ [{footer, footer_area}]
  end

  defp photo_pane(%{photo: nil} = state, area) do
    [{%Paragraph{text: photo_message(state.photo_status), block: block(" photo ")}, area}]
  end

  defp photo_pane(state, area) do
    image = if state.mode == :auto, do: state.photo.pixels, else: state.photo.cells
    title = if state.photo_status == :loading, do: "loading…", else: mode_label(state.mode)

    [{block(" photo — #{title} "), area}, {image, inner(area)}]
  end

  defp photo_message(:loading), do: "Fetching a photo from picsum.photos…"

  defp photo_message({:error, reason}),
    do: "Couldn't fetch a photo (#{inspect(reason)}). Press n to retry."

  defp block(title) do
    %Block{
      borders: [:all],
      border_type: :rounded,
      border_style: Demo.Theme.border_style(),
      title: title
    }
  end

  defp inner(%Rect{x: x, y: y, width: w, height: h}),
    do: %Rect{x: x + 1, y: y + 1, width: max(w - 2, 0), height: max(h - 2, 0)}

  defp toggle(:auto), do: :cells
  defp toggle(:cells), do: :auto

  defp cube_mode(:auto), do: :auto
  defp cube_mode(:cells), do: :braille

  defp mode_label(:auto), do: "pixels"
  defp mode_label(:cells), do: "cells"

  # Both handles are decoded once per photo: an image's protocol is fixed
  # at `Image.new/2`, so toggling swaps handles instead of re-decoding.
  defp decode_photo(bytes) do
    opts = [resize: :fit, background: @background]

    with {:ok, pixels} <- Image.new(bytes, opts),
         {:ok, cells} <- Image.new(bytes, [protocol: :halfblocks] ++ opts) do
      {:ok, %{pixels: pixels, cells: cells}}
    end
  end

  defp fetch_photo, do: Command.async(&download_photo/0, &{:photo, &1})

  defp download_photo do
    # A fresh query string per request, so every press gets a new picture.
    url = ~c"#{@photo_url}?random=#{System.unique_integer([:positive])}"

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {url, []}, [ssl: ssl, timeout: 10_000], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

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
      background: @background
    }
  end
end

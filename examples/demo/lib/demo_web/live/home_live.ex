defmodule DemoWeb.HomeLive do
  @moduledoc """
  Landing-page TUI: animated Matrix-style digital rain (Canvas labels)
  with an "EX RATATUI" `BigText` title centered on top, plus the usual
  bottom nav hints.

  Uses the reducer runtime — a `Subscription.interval` drives the rain
  animation through ticks delivered over the LiveView socket (the same
  shape as the admin panel), and a `%Event.Resize{}` reseeds the field
  to the live terminal size. `<c>`/`<a>`/`<x>`/`<q>` emit runtime intents
  the LV macro dispatches into navigation.
  """
  use PhoenixExRatatui.LiveView, runtime: :reducer

  alias Demo.{MatrixRain, UI}
  alias ExRatatui.Event.{Key, Resize}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{BigText, Block, Canvas, Clear}

  @tick_ms 90
  @repo_url "https://github.com/mcass19/phoenix_ex_ratatui"
  # `:half_width` BigText is 8 rows tall — the band height to center.
  @title_rows 8

  def tui_init(_opts), do: {:ok, %{rain: MatrixRain.new(80, 23)}}

  def tui_subscriptions(_state) do
    [Subscription.interval(:rain, @tick_ms, :tick)]
  end

  def tui_update({:info, :tick}, state) do
    {:noreply, %{state | rain: MatrixRain.tick(state.rain)}}
  end

  def tui_update({:info, _msg}, state), do: {:noreply, state}

  def tui_update({:event, %Resize{width: w, height: h}}, state) do
    # Footer takes one row; rain fills the rest.
    {:noreply, %{state | rain: MatrixRain.new(w, max(h - 1, 1))}}
  end

  def tui_update({:event, %Key{code: "c"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/chat"}]}

  def tui_update({:event, %Key{code: "a"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/admin"}]}

  def tui_update({:event, %Key{code: "x"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/coexistence"}]}

  def tui_update({:event, %Key{code: "q"}}, state),
    do: {:noreply, state, intents: [{:redirect, [external: @repo_url]}]}

  def tui_update({:event, _event}, state), do: {:noreply, state}

  def tui_render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [content_area, footer_area] = UI.split_for_footer(area)

    rain_canvas = %Canvas{
      x_bounds: {0, max(content_area.width - 1, 1)},
      y_bounds: {0, max(content_area.height - 1, 1)},
      background_color: :black,
      shapes: MatrixRain.to_labels(state.rain)
    }

    box = UI.center_box(content_area, min(content_area.width - 2, 52), 12)
    # BigText only aligns horizontally, so center the 8-row-tall title
    # band by hand inside the box's border for vertical centering too.
    title_band = UI.center_box(inner_rect(box), box.width - 2, @title_rows)
    footer = UI.nav_hints([{"c", "chat"}, {"a", "admin"}, {"x", "coexist"}, {"q", "exit"}])

    [
      {rain_canvas, content_area},
      # Clear cuts a clean rectangle out of the rain, then the framed,
      # vertically-centered title sits on top.
      {%Clear{}, box},
      {title_frame(), box},
      {title_widget(), title_band},
      {footer, footer_area}
    ]
  end

  defp inner_rect(%Rect{} = box) do
    %Rect{
      x: box.x + 1,
      y: box.y + 1,
      width: max(box.width - 2, 0),
      height: max(box.height - 2, 0)
    }
  end

  defp title_frame do
    %Block{borders: [:all], border_type: :rounded, border_style: Demo.Theme.border_style()}
  end

  defp title_widget do
    %BigText{
      lines: [%Line{spans: [%Span{content: "EX RATATUI"}]}],
      pixel_size: :half_width,
      alignment: :center,
      style: %Style{fg: :light_magenta, modifiers: [:bold]}
    }
  end
end

defmodule DemoWeb.KeysLive do
  @moduledoc """
  Key releases in the browser: a drive pad whose arrows light exactly
  while they are held, and a log of every key event as it arrives.

  `tui_mount_opts/1` returns `keyboard_enhancement: true`, so the app
  sees `"press"` when a key goes down, `"repeat"`s while the browser
  autorepeats it and `"release"` when it comes up — keyup, or the tab
  losing focus with the key still down. Without the option the same app
  would see every keydown as a `"press"` and never a release, like a
  press-only terminal.

  Callbacks runtime; `h` goes home.
  """
  use PhoenixExRatatui.LiveView

  alias Demo.UI
  alias ExRatatui.Event.Key
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, List, Paragraph}

  @arrows ~w(up down left right)
  @log_size 100

  def tui_mount_opts(_socket), do: [keyboard_enhancement: true]

  def tui_mount(_opts), do: {:ok, %{held: MapSet.new(), log: []}}

  def tui_handle_event(%Key{code: "h", kind: "press"}, state),
    do: {:noreply, state, intents: [{:navigate, "/"}]}

  def tui_handle_event(%Key{code: code, kind: kind, modifiers: mods}, state) do
    held =
      cond do
        code not in @arrows -> state.held
        kind == "release" -> MapSet.delete(state.held, code)
        true -> MapSet.put(state.held, code)
      end

    row = "#{String.pad_trailing(kind, 8)} #{inspect(code)} #{inspect(mods)}"
    {:noreply, %{state | held: held, log: Enum.take([row | state.log], @log_size)}}
  end

  def tui_handle_event(_event, state), do: {:noreply, state}

  def tui_render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [content_area, footer_area] = UI.split_for_footer(area)
    [pad_area, log_area] = Layout.split(content_area, :horizontal, [{:length, 28}, {:min, 0}])

    pad = %Paragraph{
      text: pad_text(state.held),
      alignment: :center,
      style: %Style{fg: :light_magenta, modifiers: [:bold]},
      block: block(" hold the arrows ")
    }

    log = %List{
      items: Enum.take(state.log, max(log_area.height - 2, 0)),
      style: %Style{fg: :gray},
      block: block(" events, newest first ")
    }

    [
      {pad, UI.center_box(pad_area, 28, 9)},
      {log, log_area},
      {UI.nav_hints([{"←↑↓→", "drive"}, {"h", "home"}]), footer_area}
    ]
  end

  defp pad_text(held) do
    lit = fn code, glyph -> if MapSet.member?(held, code), do: glyph, else: "·" end

    """

    #{lit.("up", "▲")}

    #{lit.("left", "◀")}     #{lit.("right", "▶")}

    #{lit.("down", "▼")}
    """
  end

  defp block(title),
    do: %Block{
      title: title,
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: :magenta}
    }
end

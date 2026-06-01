defmodule Demo.MatrixRain do
  @moduledoc """
  Pure Matrix-style "digital rain" model for the demo homepage.

  Holds one falling drop per column and renders to a list of
  `ExRatatui.Widgets.Canvas.Label` shapes — a bright head with a
  fading green trail. Deliberately free of rendering and IO so the
  field can be ticked and asserted in isolation; `DemoWeb.HomeLive`
  owns the Canvas widget and the animation tick.
  """

  alias ExRatatui.Widgets.Canvas.Label

  # Half-width katakana + digits and a few symbols — every glyph is a
  # single cell wide, so the DOM cell grid never shears. Full-width
  # kana would be double-width and tear the columns apart.
  @glyphs ~w(ｱ ｲ ｳ ｴ ｵ ｶ ｷ ｸ ｹ ｺ ｻ ｼ ｽ ｾ ｿ ﾀ ﾁ ﾂ ﾃ ﾄ ﾅ ﾆ ﾇ ﾈ ﾉ ﾊ ﾋ ﾌ ﾍ ﾎ ﾏ ﾐ 0 1 2 3 4 5 6 7 8 9 : . = *)

  @head_color {:rgb, 200, 255, 200}

  defstruct width: 0, height: 0, drops: []

  @type drop :: %{
          head: integer(),
          len: pos_integer(),
          speed: pos_integer(),
          phase: non_neg_integer(),
          glyphs: [String.t()]
        }
  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          drops: [drop()]
        }

  @doc """
  Builds a rain field sized to `width` x `height`, one freshly seeded
  drop per column. Non-positive dimensions yield an empty field.
  """
  @spec new(integer(), integer()) :: t()
  def new(width, height) when width > 0 and height > 0 do
    drops = for _ <- 1..width, do: spawn_drop(height)
    %__MODULE__{width: width, height: height, drops: drops}
  end

  def new(_width, _height), do: %__MODULE__{}

  @doc """
  Advances every drop one animation step. A drop whose trail has
  fully cleared the bottom respawns at the top with fresh glyphs,
  length, and speed.
  """
  @spec tick(t()) :: t()
  def tick(%__MODULE__{drops: drops, height: height} = rain) do
    %{rain | drops: Enum.map(drops, &advance(&1, height))}
  end

  @doc """
  Renders the current field to a flat list of `Canvas.Label` shapes —
  one per visible glyph. Canvas y grows upward, so screen row `r` maps
  to `y = height - 1 - r`.
  """
  @spec to_labels(t()) :: [Label.t()]
  def to_labels(%__MODULE__{drops: drops, height: height}) do
    for {drop, col} <- Enum.with_index(drops),
        {glyph, row, depth} <- visible_cells(drop, height) do
      %Label{x: col, y: height - 1 - row, text: glyph, color: fade_color(depth, drop.len)}
    end
  end

  # -- Internals --

  defp advance(%{head: head, speed: speed, phase: phase} = drop, height) do
    phase = phase + 1

    cond do
      rem(phase, speed) != 0 ->
        %{drop | phase: phase}

      head - drop.len >= height - 1 ->
        spawn_drop(height)

      true ->
        %{drop | head: head + 1, phase: phase}
    end
  end

  defp visible_cells(%{head: head, len: len, glyphs: glyphs}, height) do
    for depth <- 0..(len - 1),
        row = head - depth,
        row >= 0 and row < height do
      {Enum.at(glyphs, rem(row, length(glyphs))), row, depth}
    end
  end

  # The leading glyph is near-white green; the trail fades to dark
  # green by depth.
  defp fade_color(0, _len), do: @head_color

  defp fade_color(depth, len) do
    t = depth / max(len - 1, 1)
    {:rgb, round(40 - t * 40), round(255 - t * 175), round(70 - t * 50)}
  end

  defp spawn_drop(height) do
    len = 4 + :rand.uniform(max(div(height, 2), 1))

    %{
      # Start above the top edge so columns stagger in instead of all
      # appearing at once.
      head: -:rand.uniform(max(height, 1)),
      len: len,
      speed: :rand.uniform(3),
      phase: 0,
      glyphs: for(_ <- 1..(height + len), do: Enum.random(@glyphs))
    }
  end
end

defmodule Demo.MatrixRainTest do
  use ExUnit.Case, async: true

  alias Demo.MatrixRain
  alias ExRatatui.Widgets.Canvas.Label

  describe "new/2" do
    test "builds one drop per column at the given size" do
      rain = MatrixRain.new(12, 8)

      assert rain.width == 12
      assert rain.height == 8
      assert length(rain.drops) == 12
    end

    test "non-positive dimensions yield an empty field" do
      assert MatrixRain.new(0, 8) == %MatrixRain{}
      assert MatrixRain.new(10, 0) == %MatrixRain{}
    end
  end

  describe "tick/1" do
    test "advances a drop's head when its phase is due" do
      [drop] = single_drop_field(head: 0, len: 3, speed: 1) |> MatrixRain.tick() |> drops()

      assert drop.head == 1
    end

    test "holds the head until `speed` ticks elapse" do
      rain = single_drop_field(head: 0, len: 3, speed: 2)

      [after_one] = rain |> MatrixRain.tick() |> drops()
      assert after_one.head == 0

      [after_two] = rain |> MatrixRain.tick() |> MatrixRain.tick() |> drops()
      assert after_two.head == 1
    end

    test "respawns a drop once its trail clears the bottom" do
      [drop] =
        single_drop_field(head: 12, len: 3, speed: 1, height: 10) |> MatrixRain.tick() |> drops()

      assert drop.head < 1
      assert drop.glyphs != []
    end
  end

  describe "to_labels/1" do
    test "emits a label per visible glyph, all within the canvas bounds" do
      labels = single_drop_field(head: 5, len: 4, speed: 1, height: 10) |> MatrixRain.to_labels()

      assert length(labels) == 4
      assert Enum.all?(labels, fn %Label{x: x, y: y} -> x == 0 and y in 0..9 end)
    end

    test "the head glyph is bright near-white green and the trail is dimmer" do
      labels = single_drop_field(head: 5, len: 4, speed: 1, height: 10) |> MatrixRain.to_labels()

      # head is depth 0 = screen row 5 = y = (10 - 1) - 5 = 4.
      head = Enum.find(labels, &(&1.y == 4))
      assert head.color == {:rgb, 200, 255, 200}

      trail = List.delete(labels, head)
      assert trail != []
      assert Enum.all?(trail, fn %Label{color: {:rgb, _r, g, _b}} -> g < 255 end)
    end
  end

  defp drops(%MatrixRain{drops: drops}), do: drops

  # A field with a single hand-specified drop, so tick/label behavior
  # is deterministic (bypasses new/2's :rand seeding).
  defp single_drop_field(opts) do
    height = Keyword.get(opts, :height, 10)
    len = Keyword.fetch!(opts, :len)

    drop = %{
      head: Keyword.fetch!(opts, :head),
      len: len,
      speed: Keyword.fetch!(opts, :speed),
      phase: 0,
      glyphs: List.duplicate("ﾊ", height + len)
    }

    %MatrixRain{width: 1, height: height, drops: [drop]}
  end
end

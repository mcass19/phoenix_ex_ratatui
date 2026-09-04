defmodule PhoenixExRatatui.RegionsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.CellSession.{Diff, Region}
  alias PhoenixExRatatui.Regions

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}
  end

  defp region(x) do
    %Region{
      x: x,
      y: 0,
      width: 1,
      height: 1,
      pixel_width: 1,
      pixel_height: 1,
      format: :rgb8,
      data: <<0, 0, 0>>
    }
  end

  describe "payload/2" do
    test "the first frame always carries the region list, even an empty one" do
      diff = %Diff{width: 1, height: 1, ops: [], regions: []}

      {socket, payload} = Regions.payload(socket(%{tui_regions: nil}), diff)

      assert payload["regions"] == []
      assert socket.assigns.tui_regions == []
    end

    test "a changed region set is encoded and remembered" do
      diff = %Diff{width: 1, height: 1, ops: [], regions: [region(0)]}

      {socket, payload} = Regions.payload(socket(%{tui_regions: []}), diff)

      assert [[0, 0, 1, 1, "data:image/png;base64," <> _]] = payload["regions"]
      assert socket.assigns.tui_regions == [region(0)]
    end

    test "an unchanged region set is omitted from the payload and nothing is re-encoded" do
      diff = %Diff{width: 1, height: 1, ops: [], regions: [region(0)]}
      socket = socket(%{tui_regions: [region(0)]})

      {same_socket, payload} = Regions.payload(socket, diff)

      refute Map.has_key?(payload, "regions")
      assert same_socket == socket
    end

    test "a region that disappears sends an empty list so the client clears it" do
      diff = %Diff{width: 1, height: 1, ops: [], regions: []}

      {socket, payload} = Regions.payload(socket(%{tui_regions: [region(0)]}), diff)

      assert payload["regions"] == []
      assert socket.assigns.tui_regions == []
    end
  end
end

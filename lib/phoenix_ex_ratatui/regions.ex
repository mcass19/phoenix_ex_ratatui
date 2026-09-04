defmodule PhoenixExRatatui.Regions do
  @moduledoc """
  Frame-to-frame bookkeeping for pixel regions on the LiveView side.

  A `CellSession` created with a `font_size:` ships the complete list of
  pixel regions with every diff (see `ExRatatui.CellSession.Region`),
  bitmaps included. Re-encoding and re-pushing those bytes when nothing
  changed would dominate the socket traffic of a static scene, so the
  LiveView and LiveComponent remember the last list in the
  `:tui_regions` assign and only put `"regions"` on the wire when it
  differs. The client treats a missing key as "keep the overlays you
  have" and an empty list as "clear them".
  """

  alias ExRatatui.CellSession.Diff
  alias Phoenix.LiveView.Socket
  alias PhoenixExRatatui.Renderer.Html

  @doc """
  Encodes `diff` for `push_event/3`, leaving `"regions"` out when the
  region list matches the one remembered on the socket, and remembering
  the new list otherwise. Returns the (possibly updated) socket and the
  payload.
  """
  @spec payload(Socket.t(), Diff.t()) :: {Socket.t(), Html.encoded_diff()}
  def payload(%Socket{} = socket, %Diff{regions: regions} = diff) do
    if socket.assigns[:tui_regions] == regions do
      {socket, Html.encode_diff(diff, regions: false)}
    else
      {Phoenix.Component.assign(socket, :tui_regions, regions), Html.encode_diff(diff)}
    end
  end
end

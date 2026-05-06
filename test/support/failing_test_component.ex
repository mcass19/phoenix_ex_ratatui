defmodule PhoenixExRatatui.FailingTestComponent do
  @moduledoc """
  Unified-module fixture whose `tui_mount/1` always returns
  `{:error, _}`. Exercises the LiveComponent's mount-failure path:
  the linked Server's init returns `{:stop, reason}`, the parent LV
  gets the EXIT, and the component's `:tui_error` assign surfaces a
  fallback message in the next render.
  """
  use PhoenixExRatatui.LiveComponent

  def tui_mount(_opts), do: {:error, :mount_failed}
end

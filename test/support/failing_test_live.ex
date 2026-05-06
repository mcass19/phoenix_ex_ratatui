defmodule PhoenixExRatatui.FailingTestLive do
  @moduledoc """
  Unified-module fixture whose `tui_mount/1` always returns `{:error, _}`.
  Exercises the error-path branch in
  `PhoenixExRatatui.LiveView.__start_transport__/3` that captures the
  `{:error, _}` from `Transport.start_link/1` and surfaces it as a
  `:tui_error` assign instead of crashing the LV.
  """
  use PhoenixExRatatui.LiveView

  def tui_mount(_opts), do: {:error, :mount_failed}
end

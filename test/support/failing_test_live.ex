defmodule PhoenixExRatatui.FailingTestLive do
  @moduledoc """
  Test LiveView whose `:app:` always fails `mount/1`. Exercises the
  error-path branch in `PhoenixExRatatui.LiveView.__start_transport__/3`
  that captures the `{:error, _}` from `Transport.start_link/1` and
  surfaces it as a `:tui_error` assign instead of crashing the LV.
  """
  use PhoenixExRatatui.LiveView, app: PhoenixExRatatui.FailingMountApp
end

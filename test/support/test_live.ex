defmodule PhoenixExRatatui.TestLive do
  @moduledoc """
  LiveView used by `PhoenixExRatatui.LiveViewTest` to exercise the
  `__using__` macro end-to-end against `PhoenixExRatatui.TestApp`.

  Demonstrates the typical user-side shape: a one-line module that
  picks up a full-page TUI by `use`-ing the macro with an `:app:`
  pointing at any module that implements `ExRatatui.App`.
  """
  use PhoenixExRatatui.LiveView, app: PhoenixExRatatui.TestApp
end

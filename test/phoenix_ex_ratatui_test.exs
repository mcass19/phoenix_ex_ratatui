defmodule PhoenixExRatatuiTest do
  use ExUnit.Case, async: true

  doctest PhoenixExRatatui

  test "module is loaded" do
    # Trivial smoke test so `mix test` reports something other than
    # "no tests, 0 failures" while the real surface is being built.
    assert Code.ensure_loaded?(PhoenixExRatatui)
  end
end

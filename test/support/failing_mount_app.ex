defmodule PhoenixExRatatui.FailingMountApp do
  @moduledoc """
  Test fixture whose `mount/1` always returns `{:error, _}`. Used to
  exercise the Transport's mount-failure cleanup path (CellSession is
  closed, error tuple propagated to the caller).
  """
  use ExRatatui.App

  @impl true
  def mount(_opts), do: {:error, :mount_failed}

  @impl true
  def render(_state, _frame), do: []

  @impl true
  def handle_event(_event, state), do: {:noreply, state}
end

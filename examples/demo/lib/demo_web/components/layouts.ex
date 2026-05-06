defmodule DemoWeb.Layouts do
  @moduledoc """
  Root and app layouts for the demo. Kept minimal — single `<body>`
  with the LiveView script tag and a `<main>` slot.
  """
  use Phoenix.Component

  embed_templates "layouts/*"
end

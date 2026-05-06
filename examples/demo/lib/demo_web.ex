defmodule DemoWeb do
  @moduledoc """
  Boilerplate aliases / imports for the `DemoWeb` namespace, used by
  router and LiveView modules.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {DemoWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Phoenix.Component
      import Phoenix.HTML
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

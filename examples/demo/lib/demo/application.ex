defmodule Demo.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Print every phoenix_ex_ratatui telemetry event so the demo
    # exposes the integration's full lifecycle on stdout. Real apps
    # wire Telemetry.Metrics into LiveDashboard instead.
    PhoenixExRatatui.Telemetry.attach_default_logger(level: :info)

    children = [
      {Phoenix.PubSub, name: Demo.PubSub},
      DemoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

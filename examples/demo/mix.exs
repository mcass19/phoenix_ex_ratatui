defmodule Demo.MixProject do
  use Mix.Project

  def project do
    [
      app: :demo,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      # Phoenix 1.8's CodeReloader registers via Mix's listeners API.
      # Without this, every code-reloading request logs a warning.
      listeners: [Phoenix.CodeReloader],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Demo.Application, []},
      extra_applications: [:logger, :runtime_tools, :telemetry]
    ]
  end

  defp deps do
    [
      # Local checkout of the parent lib so the demo tracks unreleased
      # changes. A standalone app instead depends on the hex package.
      {:phoenix_ex_ratatui, path: "../.."},

      # Phoenix essentials
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},

      # Asset compilation
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
    ]
  end
end

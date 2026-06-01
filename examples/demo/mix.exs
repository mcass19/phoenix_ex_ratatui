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
      # changes. A standalone app instead depends on the hex package:
      #   {:phoenix_ex_ratatui, "~> 0.1"}   # pulls ex_ratatui ~> 0.10
      {:phoenix_ex_ratatui, path: "../.."},
      {:ex_ratatui, path: "../../../ex_ratatui", override: true},

      # Phoenix essentials.
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},

      # Asset compilation. esbuild is the only build tool we need —
      # no Tailwind / SCSS in this demo.
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},

      # Path-deps fallback: ex_ratatui's NIF compile path needs
      # rustler when no precompiled binary is found. Drops once
      # ex_ratatui is on hex with a release that ships CellSession.
      {:rustler, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end
end

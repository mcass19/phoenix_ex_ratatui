defmodule PhoenixExRatatui.MixProject do
  use Mix.Project

  @description "Run ExRatatui apps inside Phoenix LiveView"
  @source_url "https://github.com/mcass19/phoenix_ex_ratatui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.1.0"

  def project do
    [
      app: :phoenix_ex_ratatui,
      description: @description,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      name: "PhoenixExRatatui",
      homepage_url: @source_url,
      source_url: @source_url,
      docs: docs(),
      test_coverage: [
        summary: [threshold: 100],
        ignore_modules: [
          # Test fixtures — exercised by tests, not production surface.
          PhoenixExRatatui.TestApp,
          PhoenixExRatatui.FailingMountApp
        ]
      ],
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts/core"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "assets.install": ["cmd --cd assets npm install"],
      "assets.build": ["cmd --cd assets npm run build"]
    ]
  end

  defp deps do
    [
      # Pinned to a path during pre-release while CellSession (the
      # primitive this package depends on) lives in ex_ratatui's
      # `[Unreleased]`. Swap to `{:ex_ratatui, "~> 0.9"}` once
      # ex_ratatui cuts the release that ships CellSession.
      {:ex_ratatui, path: "../ex_ratatui"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},

      # Test
      {:floki, "~> 0.36", only: :test},
      {:stream_data, "~> 1.1", only: :test},

      # Dev
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},

      # Path-deps fallback: ex_ratatui's NIF compile path needs rustler
      # available when no precompiled binary is found for the current
      # target. Required while we depend on ex_ratatui via `path:`. Once
      # ex_ratatui ships a release with CellSession and we flip to
      # `{:ex_ratatui, "~> 0.9"}`, this dep can drop — released versions
      # ship precompiled binaries for every supported target.
      {:rustler, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @changelog_url
      },
      keywords: ~w(phoenix liveview tui terminal ratatui ex_ratatui),
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        Components: [
          PhoenixExRatatui,
          PhoenixExRatatui.LiveView,
          PhoenixExRatatui.LiveComponent
        ],
        Internals: [
          PhoenixExRatatui.Renderer.Html,
          PhoenixExRatatui.Telemetry,
          PhoenixExRatatui.Transport
        ]
      ]
    ]
  end
end

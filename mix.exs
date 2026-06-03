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
          PhoenixExRatatui.FailingMountApp,
          PhoenixExRatatui.TestLive,
          PhoenixExRatatui.TestLive.Runtime,
          PhoenixExRatatui.ReducerTestLive,
          PhoenixExRatatui.ReducerTestLive.Runtime,
          PhoenixExRatatui.FailingTestLive,
          PhoenixExRatatui.FailingTestLive.Runtime,
          PhoenixExRatatui.TestComponent,
          PhoenixExRatatui.TestComponent.Runtime,
          PhoenixExRatatui.FailingTestComponent,
          PhoenixExRatatui.FailingTestComponent.Runtime,
          PhoenixExRatatui.TestParentLive,
          PhoenixExRatatui.TestEndpoint,
          PhoenixExRatatui.TestErrorHTML
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
      {:ex_ratatui, "~> 0.10"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},

      # Test
      {:lazy_html, "~> 0.1", only: :test},
      {:stream_data, "~> 1.1", only: :test},

      # Dev
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
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
      files: ~w(lib guides package.json .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      # These references are intentional prose mentions, not links:
      # ExRatatui.Server is @moduledoc false upstream, and the
      # handle_info/2 + terminate/2 callbacks aren't autolinkable from
      # prose. Render them as plain code instead of warning.
      skip_code_autolink_to: [
        "ExRatatui.Server",
        "ExRatatui.App.handle_info/2",
        "Phoenix.LiveView.handle_info/2",
        "Phoenix.LiveView.terminate/2"
      ],
      extras: [
        "README.md": [title: "Overview"],
        "guides/getting_started.md": [title: "Getting Started"],
        "guides/telemetry.md": [title: "Telemetry"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
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

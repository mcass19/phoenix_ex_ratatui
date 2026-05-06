import Config

config :demo, DemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DemoWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Demo.PubSub,
  live_view: [signing_salt: "phoenix_ex_ratatui_demo"]

config :phoenix, :json_library, Jason

# Single esbuild profile for the demo. Bundles assets/js/app.js
# (which imports the phoenix_ex_ratatui hook from deps/) into
# priv/static/assets/app.js.
config :esbuild,
  version: "0.21.5",
  default: [
    args: ~w(
      js/app.js
      --bundle
      --target=es2020
      --outdir=../priv/static/assets
      --external:/fonts/*
      --external:/images/*
    ),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

import_config "#{config_env()}.exs"

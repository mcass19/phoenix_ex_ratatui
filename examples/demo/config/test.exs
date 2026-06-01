import Config

# The endpoint is started by the supervision tree but must not bind a
# port during tests; `server: false` keeps it dormant.
config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test_key_base_64_chars_long_padding_demo_only", 2),
  server: false

config :logger, level: :warning

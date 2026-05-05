Application.put_env(:phoenix_ex_ratatui, PhoenixExRatatui.TestEndpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_salt"],
  pubsub_server: PhoenixExRatatui.TestPubSub,
  render_errors: [formats: [html: PhoenixExRatatui.TestErrorHTML], layout: false],
  server: false,
  check_origin: false
)

defmodule PhoenixExRatatui.TestErrorHTML do
  @moduledoc false
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: PhoenixExRatatui.TestPubSub)
{:ok, _} = PhoenixExRatatui.TestEndpoint.start_link()

# Silence Phoenix LiveView's MOUNT / HANDLE EVENT debug logger so the
# test output stays readable. Tests that need to assert on log output
# already use `@tag capture_log: true` (which works at any global
# level — capture_log buffers messages regardless of Logger level).
Logger.configure(level: :warning)

ExUnit.start()

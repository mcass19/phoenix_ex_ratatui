defmodule PhoenixExRatatui.TestEndpoint do
  @moduledoc """
  Minimum `Phoenix.Endpoint` to satisfy `Phoenix.LiveViewTest.live_isolated/3`
  in this package's tests.

  Real users of `phoenix_ex_ratatui` plug it into their own application's
  endpoint — we don't ship one. This test endpoint exists purely so the
  test suite can mount our own LiveView modules without a host app.
  """

  use Phoenix.Endpoint, otp_app: :phoenix_ex_ratatui

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: {__MODULE__, :session_options, []}]]
  )

  @doc false
  # Returned tuple form lets the connect_info MFA above resolve at
  # runtime. The actual values don't matter for live_isolated, but the
  # function has to exist for the macro to compile.
  def session_options do
    [store: :cookie, key: "_phoenix_ex_ratatui_test", signing_salt: "test_salt"]
  end
end

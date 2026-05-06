import Config

if config_env() == :prod do
  raise """
  This demo isn't intended for production deployment. It's a
  reference for wiring `phoenix_ex_ratatui` into a Phoenix app.
  """
end

import Config

# ex_ratatui is a local checkout until CellSession pixel regions are
# released: build its NIF from source whatever the shell environment says.
config :rustler_precompiled, :force_build, ex_ratatui: true

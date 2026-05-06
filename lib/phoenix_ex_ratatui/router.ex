defmodule PhoenixExRatatui.Router do
  @moduledoc """
  Router macros for mounting `ExRatatui.App` modules at LiveView
  routes with one line of router code.

  ## Quick start

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import PhoenixExRatatui.Router

        scope "/" do
          pipe_through :browser

          tui_live "/tui", MyApp.Tui
        end
      end

  > #### Use non-aliased scopes for `tui_live` {: .warning}
  >
  > `tui_live` generates a wrapper module at compile time using the
  > calling router's namespace. If you put `tui_live` inside an
  > aliased scope (`scope "/", MyAppWeb do ...`), Phoenix's
  > scope-alias prepending double-prefixes the wrapper name, turning
  > `MyAppWeb.Router.TuiLive_<hash>` into
  > `MyAppWeb.MyAppWeb.Router.TuiLive_<hash>` — and you get a
  > "module not available" warning at compile time plus a 500 at
  > runtime. Wrap your `tui_live` calls in a `scope "/"` with no
  > alias prefix; the regular `live` routes inside the same scope
  > can still take fully-qualified module names like
  > `live "/admin", MyAppWeb.AdminLive`.

  Equivalent two-step pattern without `tui_live`:

      defmodule MyAppWeb.MyTuiLive do
        use PhoenixExRatatui.LiveView, app: MyApp.Tui
      end

      defmodule MyAppWeb.Router do
        # …
        scope "/", MyAppWeb do
          live "/tui", MyTuiLive
        end
      end

  Both produce identical runtime behaviour. Pick `tui_live/3` for the
  zero-boilerplate one-liner; pick the explicit form when you need to
  customise the LV (override `mount/3`, add per-route assigns,
  thread `current_user` from the session). The explicit form's
  `defoverridable` callbacks are documented in
  `PhoenixExRatatui.LiveView`.
  """

  @doc """
  Mounts an `ExRatatui.App` at `path` using `PhoenixExRatatui.LiveView`.

  At compile time, the macro generates a small wrapper module nested
  under the calling router with a stable, unique name based on
  hashing `{path, app}`, then registers a normal `live` route
  pointing at that wrapper. The wrapper is invisible to user code —
  it's a synthetic module the macro creates for `Phoenix.Router` to
  point at.

  ## Arguments

    * `path` — URL path (string literal at compile time)
    * `app` — module implementing `ExRatatui.App` (alias resolved at
      compile time via `Macro.expand/2`)
    * `opts` — keyword list forwarded to `Phoenix.LiveView.Router.live/4`'s
      fourth argument (`:as`, `:metadata`, `:container`, `:private`,
      `:session`). Defaults to `[]`.

  ## Examples

      tui_live "/tui", MyApp.Tui
      tui_live "/admin/tui", MyApp.AdminTui, container: {:div, class: "admin-tui"}

  ## Generated module name

  For a route `tui_live "/tui", MyApp.Tui` inside `MyAppWeb.Router`,
  the macro generates `MyAppWeb.Router.TuiLive_<hash>`, where
  `<hash>` is `:erlang.phash2({"/tui", MyApp.Tui})`. The name is
  stable across builds (good for incremental compilation) and
  deterministic across hosts (good for distributed-elixir scenarios).
  """
  defmacro tui_live(path, app, opts \\ []) do
    # Macro body delegates to a regular function so option-resolution
    # (Macro.expand on the app alias, hash computation, module-name
    # construction) is runtime-callable and therefore tracked by
    # `mix test --cover`. The macro itself is compile-time only and
    # `:cover` doesn't see those lines. Same shape as the analogous
    # split in `PhoenixExRatatui.LiveView.__build_using_quote__/1`.
    __build_tui_live_quote__(path, app, opts, __CALLER__)
  end

  @doc false
  # Builds the quoted block injected at a `tui_live` call site.
  # Public-but-undocumented (`@doc false`) so the test suite can
  # exercise the option-handling path directly without going
  # through compile-time macro expansion.
  def __build_tui_live_quote__(path, app, opts, caller) do
    expanded_app = Macro.expand(app, caller)
    hash = :erlang.phash2({path, expanded_app})
    full_module = Module.concat(caller.module, "TuiLive_#{hash}")

    quote do
      # Phoenix's `live/4` is a macro defined in
      # `Phoenix.LiveView.Router`, not `Phoenix.Router`. Most apps
      # `import Phoenix.LiveView.Router` in their router boilerplate
      # so they can call it unqualified, but we can't assume that —
      # users might `import PhoenixExRatatui.Router` into a router
      # that doesn't otherwise need LiveView routing imports. We
      # `require` it explicitly so the fully-qualified call below
      # always works regardless of the surrounding imports.
      require Phoenix.LiveView.Router

      defmodule unquote(full_module) do
        use PhoenixExRatatui.LiveView, app: unquote(expanded_app)
      end

      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      Phoenix.LiveView.Router.live(
        unquote(path),
        unquote(full_module),
        nil,
        unquote(opts)
      )
    end
  end
end

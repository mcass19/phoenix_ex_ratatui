defmodule PhoenixExRatatui.RouterTest do
  @moduledoc """
  Tests for `PhoenixExRatatui.Router.tui_live/3`.

  Strategy:

    * `PhoenixExRatatui.TestRouter` (in `test/support/`) compiles
      with two `tui_live` calls. If the macro is broken, the file
      won't compile and these tests won't run — implicit success
      via compilation.
    * Then we verify the macro's *observable* effects: a route
      registered at the right path with the wrapper module as the
      LV plug, the wrapper module exists at the predicted name,
      and options forwarded to `live/4` show up in route metadata.

  We don't mount a route through a real endpoint here — the
  generated wrapper module just `use`s `PhoenixExRatatui.LiveView`,
  whose mount/render flow is exhaustively covered by
  `live_view_test.exs`. Re-testing it via the router would
  duplicate effort.
  """

  use ExUnit.Case, async: true

  alias PhoenixExRatatui.Router, as: PXRRouter
  alias PhoenixExRatatui.TestRouter

  describe "__build_tui_live_quote__/4 (compile-time helper)" do
    # The `tui_live` macro delegates to `__build_tui_live_quote__/4`
    # so the option-handling path is runtime-callable (and therefore
    # tracked by mix test --cover). These tests exercise that path
    # directly without going through compile-time macro expansion.

    test "produces a quoted AST that contains the wrapper module name" do
      caller = make_caller(__MODULE__)
      ast = PXRRouter.__build_tui_live_quote__("/sample", PhoenixExRatatui.TestApp, [], caller)

      assert is_tuple(ast)
      ast_string = Macro.to_string(ast)

      hash = :erlang.phash2({"/sample", PhoenixExRatatui.TestApp})
      assert ast_string =~ "TuiLive_#{hash}"
      assert ast_string =~ "PhoenixExRatatui.TestApp"
    end

    test "different paths produce different module hashes in the AST" do
      caller = make_caller(__MODULE__)
      a = PXRRouter.__build_tui_live_quote__("/path-a", PhoenixExRatatui.TestApp, [], caller)
      b = PXRRouter.__build_tui_live_quote__("/path-b", PhoenixExRatatui.TestApp, [], caller)

      hash_a = :erlang.phash2({"/path-a", PhoenixExRatatui.TestApp})
      hash_b = :erlang.phash2({"/path-b", PhoenixExRatatui.TestApp})

      refute hash_a == hash_b
      assert Macro.to_string(a) =~ "TuiLive_#{hash_a}"
      assert Macro.to_string(b) =~ "TuiLive_#{hash_b}"
    end

    test "options are forwarded into the live(...) AST" do
      caller = make_caller(__MODULE__)

      ast =
        PXRRouter.__build_tui_live_quote__(
          "/with-opts",
          PhoenixExRatatui.TestApp,
          [as: :my_helper],
          caller
        )

      ast_string = Macro.to_string(ast)
      assert ast_string =~ "as: :my_helper"
    end

    test "the tui_live macro body itself is exercised when expanded at runtime" do
      # The `defmacro tui_live/3` body delegates to
      # `__build_tui_live_quote__/4`. That delegation runs at compile
      # time of the calling router, which `mix test --cover` doesn't
      # track (cover instrumentation activates after lib/ has
      # compiled). Forcing macro expansion at test runtime via
      # `Code.eval_string/1` exercises the delegation under active
      # cover instrumentation. Same trick used in
      # `live_view_test.exs` for the analogous gap.
      module_name =
        String.to_atom(
          "Elixir.PhoenixExRatatui.RouterTest.RuntimeMacroTest_#{System.unique_integer([:positive])}"
        )

      Code.eval_string("""
      defmodule #{inspect(module_name)} do
        use Phoenix.Router
        import PhoenixExRatatui.Router

        scope "/" do
          tui_live "/runtime_macro_test", PhoenixExRatatui.TestApp
        end
      end
      """)

      assert Code.ensure_loaded?(module_name)
      :code.purge(module_name)
      :code.delete(module_name)
    end
  end

  describe "compile-time macro expansion" do
    test "generates a wrapper module at the predicted name" do
      hash = :erlang.phash2({"/tui_test", PhoenixExRatatui.TestApp})
      expected = Module.concat(TestRouter, "TuiLive_#{hash}")

      assert Code.ensure_loaded?(expected)
      assert function_exported?(expected, :__live__, 0)
      assert function_exported?(expected, :mount, 3)
      assert function_exported?(expected, :render, 1)
      assert function_exported?(expected, :handle_event, 3)
      assert function_exported?(expected, :handle_info, 2)
    end

    test "the wrapper module is registered as a Phoenix LiveView (not LiveComponent)" do
      hash = :erlang.phash2({"/tui_test", PhoenixExRatatui.TestApp})
      module = Module.concat(TestRouter, "TuiLive_#{hash}")

      live = module.__live__()
      assert live.kind == :view
    end

    test "different (path, app) pairs produce distinct wrapper modules" do
      # Two routes in TestRouter use the same TestApp at different
      # paths. The hash includes the path, so the wrappers must not
      # collide.
      hash_a = :erlang.phash2({"/tui_test", PhoenixExRatatui.TestApp})
      hash_b = :erlang.phash2({"/tui_admin", PhoenixExRatatui.TestApp})

      module_a = Module.concat(TestRouter, "TuiLive_#{hash_a}")
      module_b = Module.concat(TestRouter, "TuiLive_#{hash_b}")

      refute module_a == module_b
      assert Code.ensure_loaded?(module_a)
      assert Code.ensure_loaded?(module_b)
    end
  end

  describe "route registration" do
    test "registers a route at the given path with the wrapper as the LV plug" do
      route = find_route("/tui_test")

      assert route, "/tui_test route should exist in TestRouter.__routes__/0"
      assert route.verb == :get

      # `Phoenix.LiveView.Router.live` registers routes with
      # `Phoenix.LiveView.Plug` as the plug, and the LV module
      # itself in the route's `:metadata` under
      # `:phoenix_live_view`. We verify both: the plug indicates
      # the route is a LiveView, the metadata identifies which
      # specific LV module backs it.
      assert route.plug == Phoenix.LiveView.Plug

      hash = :erlang.phash2({"/tui_test", PhoenixExRatatui.TestApp})
      expected_module = Module.concat(TestRouter, "TuiLive_#{hash}")

      # Phoenix LV's metadata tuple shape has shifted across
      # versions (3-tuple in older releases, 4-tuple from 1.0+
      # adding a session-name map). Match the leading element
      # — the LV module — and ignore the rest.
      assert elem(route.metadata.phoenix_live_view, 0) == expected_module
    end

    test "forwards opts to Phoenix.LiveView.Router.live/4" do
      # /tui_admin is registered with `as: :admin`, which Phoenix
      # uses to derive route helper names. Verify it landed.
      route = find_route("/tui_admin")
      assert route
      assert route.helper == "admin"
    end
  end

  defp find_route(path) do
    TestRouter.__routes__()
    |> Enum.find(fn r -> r.path == path end)
  end

  # Build a synthetic Macro.Env that satisfies the bits of the caller
  # context `__build_tui_live_quote__/4` actually reaches — namely
  # `:module` for namespacing the wrapper, and an environment for
  # `Macro.expand/2` to resolve the app alias. ExUnit's `__ENV__` is
  # close enough; we just rebind `:module` so the test asserts a
  # known-good module-name namespace.
  defp make_caller(module) do
    %{__ENV__ | module: module}
  end
end

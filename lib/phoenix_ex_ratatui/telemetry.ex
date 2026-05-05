defmodule PhoenixExRatatui.Telemetry do
  @moduledoc """
  `:telemetry` integration for `phoenix_ex_ratatui`.

  Mirrors the shape of [`ExRatatui.Telemetry`](`ExRatatui.Telemetry`)
  one layer up — events fire at the boundaries this package controls
  (LiveView mount, frame push, client input forward, Transport
  shutdown) rather than at the runtime / session layer
  `ex_ratatui` already instruments. Both fire concurrently when a
  Phoenix-driven TUI is running, and consumers attach handlers to
  whichever they need.

  ## Why a separate event tree

  `ex_ratatui` measures the App / runtime layer:
  `[:ex_ratatui, :runtime, :event]`, `[:ex_ratatui, :render, :frame]`,
  `[:ex_ratatui, :session, :lifecycle, *]`, and so on. Those events
  fire from inside `ExRatatui.Server` regardless of transport.

  `phoenix_ex_ratatui` adds events for the Phoenix-side cost:

    * mount + Transport boot (network handshake, App mount, first
      `take_cells_diff/1` returning the full grid)
    * the per-frame work the LiveView itself does on top of the
      runtime: encoding the diff to JSON, calling `push_event/3`,
      pushing over the WebSocket
    * client input being decoded and forwarded into the runtime
    * Transport teardown

  Attaching handlers to BOTH event trees gives a complete profile of
  a Phoenix-driven TUI without double-counting any single operation.

  ## Events

  All events are prefixed with `:phoenix_ex_ratatui`.

  ### Span events (`:start` / `:stop` / `:exception`)

  Each span emits three events with the suffix appended. Handlers
  typically attach to `:stop` for timing and `:exception` for
  failure tracking.

  | Event | Description | Metadata |
  | ----- | ----------- | -------- |
  | `[:phoenix_ex_ratatui, :transport, :connect]` | `PhoenixExRatatui.Transport.start_link/1` — constructs `CellSession`, boots `ExRatatui.Server`, runs `mount/1`, ships first frame. | `:mod`, `:width`, `:height`, `:target` |
  | `[:phoenix_ex_ratatui, :render, :frame]` | Per-frame Phoenix-side work: `Renderer.Html.encode_diff/1` + `Phoenix.LiveView.push_event/3`. | `:mod`, `:width`, `:height`, `:ops_count` |

  `:start` events carry `%{monotonic_time: integer, system_time: integer}`
  as measurements. `:stop` events add `:duration` (native units). On
  exception the metadata gains `:kind`, `:reason`, and `:stacktrace`.

  ### Single events

  | Event | Description | Measurements | Metadata |
  | ----- | ----------- | ------------ | -------- |
  | `[:phoenix_ex_ratatui, :transport, :disconnect]` | `Transport.stop/2` was called and the runtime server is being torn down. Does not fire on linked-process EXIT — `ex_ratatui`'s own `[:ex_ratatui, :transport, :disconnect]` covers that path. | `%{system_time: integer}` | `:mod`, `:reason` |
  | `[:phoenix_ex_ratatui, :input, :forward]` | A decoded client input is forwarded to the runtime via `Transport.push_event/2`. | `%{system_time: integer}` | `:mod`, `:event` |

  ## Attaching a default logger

      # In your Application.start/2 (or iex during dev):
      PhoenixExRatatui.Telemetry.attach_default_logger()

  That attaches a handler logging every `:stop` and single event at
  `:debug` level. Pass `attach_default_logger(level: :info)` to bump
  the level. Detach with `detach_default_logger/0`.

  Real apps wire `Telemetry.Metrics` instead — define metrics in
  your `MyApp.Telemetry` and they show up in the `LiveDashboard`'s
  Metrics tab automatically. Example:

      defmodule MyApp.Telemetry do
        import Telemetry.Metrics

        def metrics do
          [
            summary("phoenix_ex_ratatui.transport.connect.stop.duration",
              unit: {:native, :millisecond}),
            counter("phoenix_ex_ratatui.transport.disconnect"),
            summary("phoenix_ex_ratatui.render.frame.stop.duration",
              unit: {:native, :microsecond}),
            counter("phoenix_ex_ratatui.input.forward")
          ]
        end
      end
  """

  require Logger

  @doc """
  Wraps `fun` in a `:telemetry` span rooted at
  `[:phoenix_ex_ratatui | event]`.

  The `fun`'s return value is returned unchanged. The given `meta`
  is forwarded to both the `:start` and `:stop` events.
  """
  @spec span([atom(), ...], map(), (-> term())) :: term()
  def span(event, meta, fun) when is_list(event) and is_map(meta) and is_function(fun, 0) do
    :telemetry.span([:phoenix_ex_ratatui | event], meta, fn -> {fun.(), meta} end)
  end

  @doc """
  Emits a single `:telemetry` event rooted at
  `[:phoenix_ex_ratatui | event]`.

  `:system_time` is added to the measurements automatically if not
  already present.
  """
  @spec execute([atom(), ...], map(), map()) :: :ok
  def execute(event, measurements, meta)
      when is_list(event) and is_map(measurements) and is_map(meta) do
    measurements = Map.put_new_lazy(measurements, :system_time, &System.system_time/0)
    :telemetry.execute([:phoenix_ex_ratatui | event], measurements, meta)
  end

  @doc """
  Attaches a logger that prints every `phoenix_ex_ratatui` telemetry
  event. Useful during development; detach with
  `detach_default_logger/0`.

  ## Options

    * `:level` — log level (default: `:debug`).
    * `:events` — list of event suffixes to attach (default: all
      `:stop` and single events).
  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    events = Keyword.get(opts, :events, default_logger_events())

    :telemetry.attach_many(
      handler_id(),
      events,
      &__MODULE__.__default_logger_handler__/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default logger previously attached with
  `attach_default_logger/1`.
  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach(handler_id())
  end

  @doc false
  def __default_logger_handler__(event, measurements, metadata, %{level: level}) do
    Logger.log(level, fn ->
      [
        "[phoenix_ex_ratatui] ",
        Enum.map_join(event, ".", &to_string/1),
        " ",
        inspect(Map.merge(measurements, metadata),
          limit: :infinity,
          printable_limit: :infinity
        )
      ]
    end)
  end

  defp handler_id, do: "phoenix-ex-ratatui-default-logger"

  defp default_logger_events do
    [
      [:phoenix_ex_ratatui, :transport, :connect, :stop],
      [:phoenix_ex_ratatui, :transport, :connect, :exception],
      [:phoenix_ex_ratatui, :transport, :disconnect],
      [:phoenix_ex_ratatui, :render, :frame, :stop],
      [:phoenix_ex_ratatui, :render, :frame, :exception],
      [:phoenix_ex_ratatui, :input, :forward]
    ]
  end
end

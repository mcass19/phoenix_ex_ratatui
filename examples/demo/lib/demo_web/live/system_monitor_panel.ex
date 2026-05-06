defmodule DemoWeb.SystemMonitorPanel do
  @moduledoc """
  System monitor TUI as a reducer-runtime
  `PhoenixExRatatui.LiveComponent`. Port of `ex_ratatui`'s
  `system_monitor.exs` example, restructured to use `tui_init/1` +
  `tui_update/2` + `tui_subscriptions/1` instead of the callbacks-
  runtime's `tui_handle_event/2` + `Process.send_after`-based
  ticking.

  Demonstrates: reducer runtime style, `Gauge`, `Table`, periodic
  state via `Subscription.interval/3`, `/proc`-based stat collection
  driven by ticks coming through the LiveView socket.
  """
  use PhoenixExRatatui.LiveComponent, runtime: :reducer

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Subscription
  alias ExRatatui.Widgets.{Block, Gauge, Paragraph, Table}

  @refresh_interval_ms 2_000

  def tui_init(_opts), do: {:ok, collect_stats(%{})}

  def tui_subscriptions(_state) do
    [Subscription.interval(:refresh, @refresh_interval_ms, :refresh)]
  end

  def tui_update({:event, %Key{code: "r"}}, state),
    do: {:noreply, collect_stats(state)}

  def tui_update({:event, %Key{code: "b"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/"}]}

  def tui_update({:event, %Key{code: "c"}}, state),
    do: {:noreply, state, intents: [{:navigate, "/chat"}]}

  def tui_update({:event, _event}, state), do: {:noreply, state}

  def tui_update({:info, :refresh}, state), do: {:noreply, collect_stats(state)}
  def tui_update({:info, _msg}, state), do: {:noreply, state}

  def tui_render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}])

    [left_col, right_col] =
      Layout.split(body_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [cpu_area, mem_area, disk_area] =
      Layout.split(left_col, :vertical, [{:length, 3}, {:length, 3}, {:length, 3}])

    [net_area, beam_area] =
      Layout.split(right_col, :vertical, [{:length, 7}, {:min, 0}])

    [
      {header_widget(state), header_area},
      {cpu_temp_widget(state), cpu_area},
      {memory_widget(state), mem_area},
      {disk_widget(state), disk_area},
      {network_widget(state), net_area},
      {beam_widget(state), beam_area},
      {Demo.UI.nav_hints([{"r", "refresh"}, {"c", "chat"}, {"b", "home"}]), footer_area}
    ]
  end

  # -- Widget builders --

  defp header_widget(state) do
    %Paragraph{
      text: "  #{state.hostname}    Uptime: #{format_uptime(state.uptime_seconds)}",
      style: %Style{fg: :light_magenta, modifiers: [:bold]},
      block: %Block{
        title: " System Monitor ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :magenta}
      }
    }
  end

  defp cpu_temp_widget(state) do
    {ratio, label, color} =
      case state.cpu_temp do
        nil ->
          {0.0, "N/A", :dark_gray}

        temp ->
          color =
            cond do
              temp >= 70 -> :red
              temp >= 55 -> :yellow
              true -> :green
            end

          {min(temp / 85.0, 1.0), "#{Float.round(temp, 1)}C", color}
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: color},
      block: %Block{
        title: " CPU Temp ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp memory_widget(state) do
    {ratio, label} =
      case state.memory do
        %{total: total, used: used} when total > 0 ->
          {used / total, "#{format_mb(used)} / #{format_mb(total)} MB"}

        _ ->
          {0.0, "N/A"}
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: gauge_color(ratio)},
      block: %Block{
        title: " Memory ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp disk_widget(state) do
    {ratio, label} =
      case state.disk do
        %{total: total, used: used} when total > 0 ->
          {used / total, "#{format_gb(used)} / #{format_gb(total)} GB"}

        _ ->
          {0.0, "N/A"}
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: gauge_color(ratio)},
      block: %Block{
        title: " Disk (/) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp gauge_color(ratio) do
    cond do
      ratio >= 0.9 -> :red
      ratio >= 0.7 -> :yellow
      true -> :green
    end
  end

  defp network_widget(state) do
    rows = Enum.map(state.interfaces, fn {name, ip} -> [name, ip] end)
    rows = if rows == [], do: [["--", "no interfaces"]], else: rows

    %Table{
      header: ["Interface", "IP Address"],
      rows: rows,
      widths: [{:percentage, 40}, {:percentage, 60}],
      style: %Style{fg: :white},
      block: %Block{
        title: " Network ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp beam_widget(state) do
    beam = state.beam

    lines = [
      "  Processes:  #{beam.processes}",
      "  Ports:      #{beam.ports}",
      "  Total mem:  #{format_mb(beam.total_memory)} MB",
      "  Proc mem:   #{format_mb(beam.process_memory)} MB",
      "  ETS mem:    #{format_mb(beam.ets_memory)} MB",
      "  Atoms:      #{beam.atom_count}"
    ]

    %Paragraph{
      text: Enum.join(lines, "\n"),
      style: %Style{fg: :white},
      block: %Block{
        title: " BEAM ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  # -- Data collection --

  defp collect_stats(prev) do
    %{
      hostname: Map.get_lazy(prev, :hostname, &read_hostname/0),
      cpu_temp: read_cpu_temp(),
      memory: read_memory(),
      disk: read_disk(),
      interfaces: read_interfaces(),
      beam: read_beam_stats(),
      uptime_seconds: read_uptime()
    }
  end

  defp read_hostname do
    case File.read("/etc/hostname") do
      {:ok, name} -> String.trim(name)
      _ -> to_string(:net_adm.localhost())
    end
  end

  defp read_cpu_temp do
    case File.read("/sys/class/thermal/thermal_zone0/temp") do
      {:ok, content} -> content |> String.trim() |> String.to_integer() |> Kernel./(1000.0)
      _ -> nil
    end
  end

  defp read_memory do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        info =
          content
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ~r/:\s+/) do
              [key, value | _] ->
                case Integer.parse(value) do
                  {kb, _} -> Map.put(acc, key, kb)
                  :error -> acc
                end

              _ ->
                acc
            end
          end)

        total = Map.get(info, "MemTotal", 0)
        available = Map.get(info, "MemAvailable", 0)
        %{total: total * 1024, used: (total - available) * 1024}

      _ ->
        %{total: 0, used: 0}
    end
  end

  defp read_disk do
    output = :os.cmd(~c"df -k / 2>/dev/null") |> to_string()

    case String.split(output, "\n", trim: true) do
      [_header, data_line | _] ->
        case String.split(data_line, ~r/\s+/) do
          [_, total_str, used_str | _] ->
            %{
              total: String.to_integer(total_str) * 1024,
              used: String.to_integer(used_str) * 1024
            }

          _ ->
            %{total: 0, used: 0}
        end

      _ ->
        %{total: 0, used: 0}
    end
  rescue
    _ -> %{total: 0, used: 0}
  end

  defp read_interfaces do
    case :inet.getifaddrs() do
      {:ok, addrs} ->
        Enum.flat_map(addrs, fn {name, opts} ->
          name_str = to_string(name)

          if name_str in ["lo", "lo0"] do
            []
          else
            ips =
              opts
              |> Keyword.get_values(:addr)
              |> Enum.filter(&(tuple_size(&1) == 4))
              |> Enum.map(&ip_to_string/1)

            case ips do
              [ip | _] -> [{name_str, ip}]
              [] -> [{name_str, "--"}]
            end
          end
        end)

      _ ->
        []
    end
  end

  defp read_beam_stats do
    mem = :erlang.memory()

    %{
      processes: :erlang.system_info(:process_count),
      ports: :erlang.system_info(:port_count),
      total_memory: Keyword.get(mem, :total, 0),
      process_memory: Keyword.get(mem, :processes_used, 0),
      ets_memory: Keyword.get(mem, :ets, 0),
      atom_count: :erlang.system_info(:atom_count)
    }
  end

  defp read_uptime do
    case File.read("/proc/uptime") do
      {:ok, content} ->
        content |> String.split(" ") |> List.first() |> String.to_float() |> trunc()

      _ ->
        {uptime_ms, _} = :erlang.statistics(:wall_clock)
        div(uptime_ms, 1000)
    end
  end

  # -- Formatting helpers --

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    mins = div(rem(seconds, 3_600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{mins}m"
      hours > 0 -> "#{hours}h #{mins}m"
      true -> "#{mins}m"
    end
  end

  defp format_mb(bytes) when is_integer(bytes) do
    (bytes / (1024 * 1024)) |> Float.round(1) |> to_string()
  end

  defp format_mb(_), do: "0"

  defp format_gb(bytes) when is_integer(bytes) do
    (bytes / (1024 * 1024 * 1024)) |> Float.round(1) |> to_string()
  end

  defp format_gb(_), do: "0"

  defp ip_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
end

defmodule DemoWeb.ChatLive do
  @moduledoc """
  Full-page chat TUI — port of `ex_ratatui`'s `chat_interface.exs`
  example into a `PhoenixExRatatui.LiveView` unified module.

  Demonstrates: `Markdown`, `Textarea`, `Throbber`, `Popup`,
  `WidgetList`, `SlashCommands`, `Scrollbar` — most of ExRatatui's
  rich widget catalogue running over the LiveView socket as cell
  diffs.

  ## Controls

    * `Ctrl+S` — send message
    * `Enter` — newline (or pick autocomplete suggestion)
    * `/` — trigger slash command autocomplete
    * `Escape` — close autocomplete popup
    * `Up`/`Down` — navigate autocomplete or scroll messages
    * `Ctrl+Q` — back to the home screen (emits `{:navigate, "/"}`)
  """
  use PhoenixExRatatui.LiveView

  alias Demo.UI
  alias ExRatatui.Event.Key
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Block,
    Markdown,
    Paragraph,
    Scrollbar,
    SlashCommands,
    Textarea,
    Throbber,
    WidgetList
  }

  alias ExRatatui.Widgets.SlashCommands.Command

  @commands [
    %Command{name: "help", description: "Show available commands"},
    %Command{name: "clear", description: "Clear chat history"},
    %Command{name: "model", description: "Switch AI model"},
    %Command{name: "system", description: "Set system prompt"},
    %Command{name: "back", description: "Return to home screen", aliases: ["home"]}
  ]

  @ai_responses [
    """
    # Welcome!

    I'm a fake AI assistant running entirely as a TUI inside Phoenix LiveView.
    Try asking me anything, or use `/help` for commands.

    - **Markdown rendering** — this whole bubble is rendered by `Markdown`
    - **Slash commands** — type `/` to see autocomplete
    - **Multi-line input** — `Enter` for newline, `Ctrl+S` to send
    """,
    """
    Sure! Here's a quick example:

    ```elixir
    defmodule MyApp do
      def hello(name) do
        "Hello, \#{name}!"
      end
    end
    ```

    `defmodule` defines a module; functions are defined with `def`.
    """,
    """
    Here are some **key concepts**:

    1. *Pattern matching* — `=` matches rather than assigns
    2. *Immutability* — data is never modified in place
    3. *Processes* — lightweight concurrent units of execution

    > "Let it crash" — the OTP philosophy.
    """,
    """
    Let me break that down:

    - First, understand the **problem space**
    - Then look at possible *solutions*
    - Finally, pick the best approach

    `GenServer` gives us state management, message passing, and
    fault tolerance via supervisors.
    """
  ]

  @loading_delay_ms 1500
  @throbber_tick_ms 80

  def tui_mount(_opts) do
    textarea_state = ExRatatui.textarea_new()

    state = %{
      textarea: textarea_state,
      messages: [{:ai, Enum.at(@ai_responses, 0)}],
      response_index: 1,
      scroll_offset: 0,
      throbber_step: 0,
      loading: false,
      loading_started_at: nil,
      show_autocomplete: false,
      autocomplete_selected: 0,
      autocomplete_matches: []
    }

    {:ok, state}
  end

  # -- Render --

  def tui_render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, messages_area, input_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 1},
        {:min, 5},
        {:length, 5},
        {:length, 1}
      ])

    widgets = []

    header = %Paragraph{
      text: "  phoenix_ex_ratatui — chat",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    widgets = [{header, header_area} | widgets]

    msg_content_area = %Rect{
      x: messages_area.x,
      y: messages_area.y,
      width: messages_area.width - 1,
      height: messages_area.height
    }

    widgets = [{build_message_list(state), msg_content_area} | widgets]

    total_lines = total_message_lines(state.messages)
    visible_height = max(1, messages_area.height - 2)

    scrollbar = %Scrollbar{
      content_length: max(1, total_lines - visible_height),
      position: state.scroll_offset,
      orientation: :vertical_right,
      viewport_content_length: visible_height,
      thumb_style: %Style{fg: :cyan},
      track_style: %Style{fg: :dark_gray}
    }

    scrollbar_area = %Rect{
      x: messages_area.x + messages_area.width - 1,
      y: messages_area.y,
      width: 1,
      height: messages_area.height
    }

    widgets = [{scrollbar, scrollbar_area} | widgets]

    widgets =
      if state.loading do
        throbber = %Throbber{
          label: " AI is thinking...",
          step: state.throbber_step,
          throbber_set: :braille,
          style: %Style{fg: :yellow},
          throbber_style: %Style{fg: :yellow, modifiers: [:bold]}
        }

        throbber_area = %Rect{
          x: messages_area.x + 1,
          y: messages_area.y + messages_area.height - 1,
          width: min(30, messages_area.width - 2),
          height: 1
        }

        [{throbber, throbber_area} | widgets]
      else
        widgets
      end

    textarea = %Textarea{
      state: state.textarea,
      style: %Style{fg: :white},
      cursor_style: %Style{bg: :white, fg: :black},
      placeholder: "Type a message... (Ctrl+S to send, / for commands)",
      placeholder_style: %Style{fg: :dark_gray},
      block: %Block{
        title: "Message",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    widgets = [{textarea, input_area} | widgets]

    footer =
      UI.nav_hints([
        {"Ctrl+S", "send"},
        {"Enter", "newline"},
        {"/", "commands"},
        {"Ctrl+Q", "home"}
      ])

    widgets = [{footer, footer_area} | widgets]

    widgets =
      if state.show_autocomplete and state.autocomplete_matches != [] do
        popup_widgets =
          SlashCommands.render_autocomplete(state.autocomplete_matches,
            area: area,
            selected: state.autocomplete_selected,
            percent_width: 40,
            percent_height: 30,
            highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]}
          )

        popup_widgets ++ widgets
      else
        widgets
      end

    Enum.reverse(widgets)
  end

  defp build_message_list(state) do
    items =
      Enum.flat_map(state.messages, fn
        {:user, text} ->
          label = %Paragraph{
            text: " You ",
            style: %Style{fg: :black, bg: :green, modifiers: [:bold]}
          }

          content = %Paragraph{text: text, style: %Style{fg: :white}, wrap: true}
          lines = text |> String.split("\n") |> length()
          spacer = %Paragraph{text: ""}

          [{label, 1}, {content, max(1, lines)}, {spacer, 1}]

        {:ai, text} ->
          label = %Paragraph{
            text: " AI ",
            style: %Style{fg: :black, bg: :magenta, modifiers: [:bold]}
          }

          content = %Markdown{content: String.trim(text), wrap: true}
          lines = text |> String.trim() |> String.split("\n") |> length()
          spacer = %Paragraph{text: ""}

          [{label, 1}, {content, max(1, lines)}, {spacer, 1}]
      end)

    %WidgetList{
      items: items,
      scroll_offset: state.scroll_offset,
      block: %Block{
        title: "Chat (#{length(state.messages)} messages)",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp total_message_lines(messages) do
    Enum.reduce(messages, 0, fn
      {:user, text}, acc ->
        acc + 1 + max(1, text |> String.split("\n") |> length()) + 1

      {:ai, text}, acc ->
        acc + 1 + max(1, text |> String.trim() |> String.split("\n") |> length()) + 1
    end)
  end

  # -- Events --

  # Guards can't `in` a runtime list; defer the modifier check to the
  # body and dispatch via a small helper.
  def tui_handle_event(%Key{code: "q", modifiers: mods}, state) do
    if ctrl?(mods) do
      {:noreply, state, intents: [{:navigate, "/"}]}
    else
      ExRatatui.textarea_handle_key(state.textarea, "q", mods)
      {:noreply, check_slash_command(state)}
    end
  end

  def tui_handle_event(%Key{code: "escape"}, state) do
    {:noreply, %{state | show_autocomplete: false}}
  end

  def tui_handle_event(%Key{code: "s", modifiers: mods}, state) do
    if ctrl?(mods) do
      {:noreply, submit_message(state), commands: throbber_tick_command(true)}
    else
      ExRatatui.textarea_handle_key(state.textarea, "s", mods)
      {:noreply, check_slash_command(state)}
    end
  end

  def tui_handle_event(%Key{code: "enter"}, state) do
    if state.show_autocomplete do
      execute_command(state)
    else
      ExRatatui.textarea_handle_key(state.textarea, "enter", [])
      {:noreply, state}
    end
  end

  def tui_handle_event(%Key{code: "up"}, state) do
    if state.show_autocomplete do
      new_sel = max(0, state.autocomplete_selected - 1)
      {:noreply, %{state | autocomplete_selected: new_sel}}
    else
      {:noreply, %{state | scroll_offset: max(0, state.scroll_offset - 1)}}
    end
  end

  def tui_handle_event(%Key{code: "down"}, state) do
    if state.show_autocomplete do
      max_sel = max(0, length(state.autocomplete_matches) - 1)
      new_sel = min(max_sel, state.autocomplete_selected + 1)
      {:noreply, %{state | autocomplete_selected: new_sel}}
    else
      {:noreply, %{state | scroll_offset: state.scroll_offset + 1}}
    end
  end

  def tui_handle_event(%Key{code: code, modifiers: mods}, state) do
    ExRatatui.textarea_handle_key(state.textarea, code, mods)
    {:noreply, check_slash_command(state)}
  end

  def tui_handle_event(_event, state), do: {:noreply, state}

  defp ctrl?(mods) when is_list(mods), do: :ctrl in mods
  defp ctrl?(_), do: false

  # -- Loading / throbber tick --

  def tui_handle_info(:throbber_tick, %{loading: false} = state), do: {:noreply, state}

  def tui_handle_info(:throbber_tick, state) do
    elapsed = System.monotonic_time(:millisecond) - state.loading_started_at

    if elapsed > @loading_delay_ms do
      response = Enum.at(@ai_responses, rem(state.response_index, length(@ai_responses)))
      new_messages = state.messages ++ [{:ai, response}]

      {:noreply,
       %{
         state
         | loading: false,
           loading_started_at: nil,
           messages: new_messages,
           response_index: state.response_index + 1
       }}
    else
      {:noreply, %{state | throbber_step: state.throbber_step + 1},
       commands: throbber_tick_command(true)}
    end
  end

  def tui_handle_info(_msg, state), do: {:noreply, state}

  defp throbber_tick_command(true) do
    [ExRatatui.Command.send_after(@throbber_tick_ms, :throbber_tick)]
  end

  defp submit_message(state) do
    value = state.textarea |> ExRatatui.textarea_get_value() |> String.trim()

    if value == "" do
      state
    else
      ExRatatui.textarea_set_value(state.textarea, "")

      %{
        state
        | messages: state.messages ++ [{:user, value}],
          loading: true,
          loading_started_at: System.monotonic_time(:millisecond),
          show_autocomplete: false
      }
    end
  end

  defp check_slash_command(state) do
    value = ExRatatui.textarea_get_value(state.textarea)

    case SlashCommands.parse(value) do
      {:command, prefix} ->
        matches = SlashCommands.match_commands(@commands, prefix)

        %{
          state
          | show_autocomplete: matches != [],
            autocomplete_matches: matches,
            autocomplete_selected: 0
        }

      :no_command ->
        %{state | show_autocomplete: false, autocomplete_matches: []}
    end
  end

  defp execute_command(state) do
    case Enum.at(state.autocomplete_matches, state.autocomplete_selected) do
      nil ->
        {:noreply, state}

      %Command{name: "clear"} ->
        ExRatatui.textarea_set_value(state.textarea, "")
        {:noreply, %{state | messages: [], show_autocomplete: false, scroll_offset: 0}}

      %Command{name: "back"} ->
        ExRatatui.textarea_set_value(state.textarea, "")
        {:noreply, %{state | show_autocomplete: false}, intents: [{:navigate, "/"}]}

      %Command{name: "help"} ->
        ExRatatui.textarea_set_value(state.textarea, "")

        help = """
        # Available Commands

        | Command | Description |
        |---------|-------------|
        | `/help` | Show this help message |
        | `/clear` | Clear chat history |
        | `/model` | Switch AI model |
        | `/system` | Set system prompt |
        | `/back` | Return to home screen |

        **Keyboard shortcuts:** `Ctrl+S` send · `Enter` newline ·
        `Ctrl+Q` home · `Up/Down` scroll
        """

        {:noreply, %{state | messages: state.messages ++ [{:ai, help}], show_autocomplete: false}}

      %Command{name: name} ->
        ExRatatui.textarea_set_value(state.textarea, "")

        msg = "Command `/#{name}` is not implemented yet."

        {:noreply, %{state | messages: state.messages ++ [{:ai, msg}], show_autocomplete: false}}
    end
  end
end

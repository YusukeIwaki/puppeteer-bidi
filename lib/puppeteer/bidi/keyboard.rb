# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Keyboard class for keyboard input operations
    # Based on Puppeteer's BidiKeyboard implementation
    class Keyboard
      def initialize(page, browsing_context)
        @page = page
        @browsing_context = browsing_context
        @pressed_keys = Set.new
      end

      # Press key down
      # @param key [String] Key name (e.g., 'a', 'Enter', 'ArrowLeft')
      # @param text [String, nil] Text to insert (for CDP compatibility, not used in BiDi)
      # @param commands [Array<String>, nil] Commands to trigger (for CDP compatibility, not used in BiDi)
      def down(key, text: nil, commands: nil)
        # Note: text and commands parameters exist for CDP compatibility but are not used in BiDi
        actions = [{
          type: 'keyDown',
          value: get_bidi_key_value(key)
        }]

        perform_actions(actions)
        @pressed_keys.add(key)
      end

      # Release key
      # @param key [String] Key name
      def up(key)
        actions = [{
          type: 'keyUp',
          value: get_bidi_key_value(key)
        }]

        perform_actions(actions)
        @pressed_keys.delete(key)
      end

      # Press and release a key
      # @param key [String] Key name
      # @param delay [Numeric, nil] Delay between keydown and keyup in milliseconds
      # @param text [String, nil] Text to insert (for CDP compatibility, not used in BiDi)
      # @param commands [Array<String>, nil] Commands to trigger (for CDP compatibility, not used in BiDi)
      def press(key, delay: nil, text: nil, commands: nil)
        # Note: text and commands parameters exist for CDP compatibility but are not used in BiDi
        actions = [{ type: 'keyDown', value: get_bidi_key_value(key) }]

        if delay
          actions << {
            type: 'pause',
            duration: delay.to_i
          }
        end

        actions << { type: 'keyUp', value: get_bidi_key_value(key) }

        perform_actions(actions)
      end

      # Type text (types each character with keydown/keyup events)
      # @param text [String] Text to type
      # @param delay [Numeric] Delay between each character in milliseconds
      def type(text, delay: 0)
        actions = []

        # Split text into individual code points (handles multi-byte Unicode correctly)
        text.each_char do |char|
          key_value = get_bidi_key_value(char)

          actions << { type: 'keyDown', value: key_value }
          actions << { type: 'keyUp', value: key_value }

          if delay > 0
            actions << {
              type: 'pause',
              duration: delay.to_i
            }
          end
        end

        perform_actions(actions)
      end

      # Send character directly (bypasses keyboard events, uses execCommand)
      # @param char [String] Character to send
      def send_character(char)
        # Validate: cannot send more than 1 character
        # Measures the number of code points rather than UTF-16 code units
        if char.chars.length > 1
          raise ArgumentError, 'Cannot send more than 1 character.'
        end

        # Get the focused frame (may be an iframe)
        focused_frame = @page.focused_frame

        # Execute insertText in the focused frame's isolated realm
        focused_frame.isolated_realm.call_function(
          'function(char) { document.execCommand("insertText", false, char); }',
          false,
          arguments: [{ type: 'string', value: char }]
        )
      end

      private

      # Convert key name to BiDi protocol value
      # @param key [String] Key name
      # @return [String] BiDi key value (Unicode character or escape sequence)
      def get_bidi_key_value(key)
        # Normalize line breaks
        normalized_key = case key
                         when "\r", "\n" then 'Enter'
                         else key
                         end

        # If it's a single character (measured by code points), return as-is
        if normalized_key.length == 1
          return normalized_key
        end

        # Map key names to WebDriver BiDi Unicode values
        # Reference: https://w3c.github.io/webdriver/#keyboard-actions
        case normalized_key
        # Modifier keys
        when 'Shift', 'ShiftLeft' then "\uE008"
        when 'ShiftRight' then "\uE050"
        when 'Ctrl', 'Control', 'CtrlLeft', 'ControlLeft' then "\uE009"
        when 'CtrlRight', 'ControlRight' then "\uE051"
        when 'Alt', 'AltLeft' then "\uE00A"
        when 'AltRight' then "\uE052"
        when 'Meta', 'MetaLeft' then "\uE03D"
        when 'MetaRight' then "\uE053"

        when 'CtrlOrMeta', 'ControlOrMeta' then (
          if RUBY_PLATFORM.include?('darwin')
            "\uE03D" # Meta
          else
            "\uE009" # Control
          end
        )

        # Whitespace keys
        when 'Enter', 'NumpadEnter' then "\uE007"
        when 'Tab' then "\uE004"
        when 'Space' then "\uE00D"

        # Editing keys
        when 'Backspace' then "\uE003"
        when 'Delete' then "\uE017"
        when 'Escape' then "\uE00C"

        # Navigation keys
        when 'ArrowUp' then "\uE013"
        when 'ArrowDown' then "\uE015"
        when 'ArrowLeft' then "\uE012"
        when 'ArrowRight' then "\uE014"
        when 'Home' then "\uE011"
        when 'End' then "\uE010"
        when 'PageUp' then "\uE00E"
        when 'PageDown' then "\uE00F"
        when 'Insert' then "\uE016"

        # Function keys
        when 'F1' then "\uE031"
        when 'F2' then "\uE032"
        when 'F3' then "\uE033"
        when 'F4' then "\uE034"
        when 'F5' then "\uE035"
        when 'F6' then "\uE036"
        when 'F7' then "\uE037"
        when 'F8' then "\uE038"
        when 'F9' then "\uE039"
        when 'F10' then "\uE03A"
        when 'F11' then "\uE03B"
        when 'F12' then "\uE03C"

        # Numpad
        when 'Numpad0' then "\uE01A"
        when 'Numpad1' then "\uE01B"
        when 'Numpad2' then "\uE01C"
        when 'Numpad3' then "\uE01D"
        when 'Numpad4' then "\uE01E"
        when 'Numpad5' then "\uE01F"
        when 'Numpad6' then "\uE020"
        when 'Numpad7' then "\uE021"
        when 'Numpad8' then "\uE022"
        when 'Numpad9' then "\uE023"
        when 'NumpadMultiply' then "\uE024"
        when 'NumpadAdd' then "\uE025"
        when 'NumpadSubtract' then "\uE027"
        when 'NumpadDecimal' then "\uE028"
        when 'NumpadDivide' then "\uE029"

        # Key codes - convert to actual characters
        when 'Digit0' then '0'
        when 'Digit1' then '1'
        when 'Digit2' then '2'
        when 'Digit3' then '3'
        when 'Digit4' then '4'
        when 'Digit5' then '5'
        when 'Digit6' then '6'
        when 'Digit7' then '7'
        when 'Digit8' then '8'
        when 'Digit9' then '9'

        when 'KeyA' then 'a'
        when 'KeyB' then 'b'
        when 'KeyC' then 'c'
        when 'KeyD' then 'd'
        when 'KeyE' then 'e'
        when 'KeyF' then 'f'
        when 'KeyG' then 'g'
        when 'KeyH' then 'h'
        when 'KeyI' then 'i'
        when 'KeyJ' then 'j'
        when 'KeyK' then 'k'
        when 'KeyL' then 'l'
        when 'KeyM' then 'm'
        when 'KeyN' then 'n'
        when 'KeyO' then 'o'
        when 'KeyP' then 'p'
        when 'KeyQ' then 'q'
        when 'KeyR' then 'r'
        when 'KeyS' then 's'
        when 'KeyT' then 't'
        when 'KeyU' then 'u'
        when 'KeyV' then 'v'
        when 'KeyW' then 'w'
        when 'KeyX' then 'x'
        when 'KeyY' then 'y'
        when 'KeyZ' then 'z'

        # Punctuation
        when 'Semicolon' then ';'
        when 'Equal' then '='
        when 'Comma' then ','
        when 'Minus' then '-'
        when 'Period' then '.'
        when 'Slash' then '/'
        when 'Backquote' then '`'
        when 'BracketLeft' then '['
        when 'Backslash' then '\\'
        when 'BracketRight' then ']'
        when 'Quote' then "'"

        else
          raise "Unknown key: #{normalized_key.inspect}"
        end
      end

      # Perform input actions via BiDi
      def perform_actions(action_list)
        @browsing_context.perform_actions([
          {
            type: 'key',
            id: 'default keyboard',
            actions: action_list
          }
        ]).wait
      end
    end
  end
end

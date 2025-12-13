# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Mouse class for mouse input operations
    # Based on Puppeteer's BidiMouse implementation
    class Mouse
      # Mouse button constants
      LEFT = 'left'
      RIGHT = 'right'
      MIDDLE = 'middle'
      BACK = 'back'
      FORWARD = 'forward'

      def initialize(browsing_context)
        @browsing_context = browsing_context
        @x = 0
        @y = 0
      end

      # Move mouse to coordinates
      # @param x [Numeric] X coordinate
      # @param y [Numeric] Y coordinate
      # @param steps [Integer] Number of intermediate steps (for smooth movement)
      def move(x, y, steps: 1)
        from_x = @x
        from_y = @y

        @x = x
        @y = y

        actions = []
        (1..steps).each do |step|
          # Linear interpolation
          intermediate_x = from_x + (x - from_x) * step / steps
          intermediate_y = from_y + (y - from_y) * step / steps

          actions << {
            type: 'pointerMove',
            x: intermediate_x.to_i,
            y: intermediate_y.to_i
          }
        end

        perform_actions(actions)
      end

      # Press mouse button down
      # @param button [String] Mouse button ('left', 'right', 'middle', 'back', 'forward')
      def down(button: LEFT)
        actions = [{
          type: 'pointerDown',
          button: button_to_bidi(button)
        }]
        perform_actions(actions)
      end

      # Release mouse button
      # @param button [String] Mouse button
      def up(button: LEFT)
        actions = [{
          type: 'pointerUp',
          button: button_to_bidi(button)
        }]
        perform_actions(actions)
      end

      # Click at coordinates
      # @param x [Numeric] X coordinate
      # @param y [Numeric] Y coordinate
      # @param button [String] Mouse button
      # @param count [Integer] Number of clicks (1 for single, 2 for double, 3 for triple)
      # @param delay [Numeric] Delay between down and up in milliseconds
      def click(x, y, button: LEFT, count: 1, delay: nil)
        actions = []

        # Move to coordinates
        if @x != x || @y != y
          actions << {
            type: 'pointerMove',
            x: x.to_i,
            y: y.to_i,
            origin: 'viewport'  # BiDi expects string, not hash
          }
        end

        @x = x
        @y = y

        bidi_button = button_to_bidi(button)

        # Perform clicks
        count.times do
          actions << {
            type: 'pointerDown',
            button: bidi_button
          }

          if delay
            actions << {
              type: 'pause',
              duration: delay.to_i
            }
          end

          actions << {
            type: 'pointerUp',
            button: bidi_button
          }
        end

        perform_actions(actions)
      end

      # Scroll using mouse wheel
      # @param delta_x [Numeric] Horizontal scroll amount
      # @param delta_y [Numeric] Vertical scroll amount
      def wheel(delta_x: 0, delta_y: 0)
        @browsing_context.perform_actions([
          {
            type: 'wheel',
            id: '__puppeteer_wheel',
            actions: [
              {
                type: 'scroll',
                x: @x.to_i,
                y: @y.to_i,
                deltaX: delta_x.to_i,
                deltaY: delta_y.to_i
              }
            ]
          }
        ]).wait
      end

      # Reset mouse state
      # Resets position to origin and releases all pressed buttons
      def reset
        @x = 0
        @y = 0
        @browsing_context.release_actions.wait
      end

      private

      # Convert mouse button name to BiDi button number
      def button_to_bidi(button)
        case button
        when LEFT then 0
        when MIDDLE then 1
        when RIGHT then 2
        when BACK then 3
        when FORWARD then 4
        else 0
        end
      end

      # Perform input actions via BiDi
      def perform_actions(action_list)
        @browsing_context.perform_actions([
          {
            type: 'pointer',
            id: 'default mouse',
            actions: action_list
          }
        ]).wait
      end
    end
  end
end

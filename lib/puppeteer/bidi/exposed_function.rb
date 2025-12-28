# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Puppeteer
  module Bidi
    # ExposedFunction manages the lifecycle of a function exposed to the page.
    # It uses script.message to receive calls from the page.
    class ExposedFunction
      # Raised to signal a non-Exception value should be thrown to the page.
      class ThrownValue < StandardError
        attr_reader :value #: untyped

        # @rbs value: untyped -- Value to throw
        # @rbs return: void
        def initialize(value)
          @value = value
          super("Thrown value")
        end
      end

      # Create and initialize an exposed function.
      # @rbs frame: Frame -- Frame to expose the function in
      # @rbs name: String -- Function name
      # @rbs apply: Proc? -- Ruby callable to execute
      # @rbs isolate: bool -- Whether to expose in the isolated realm
      # @rbs return: ExposedFunction -- Initialized exposed function
      def self.from(frame, name, apply = nil, isolate: false, &block)
        handler = apply || block
        unless handler&.respond_to?(:call)
          raise ArgumentError, "expose_function requires a callable"
        end

        func = new(frame, name, handler, isolate: isolate)
        func.send(:setup)
        func
      end

      attr_reader :name #: String

      # @rbs frame: Frame -- Frame to expose the function in
      # @rbs name: String -- Function name
      # @rbs apply: Proc -- Ruby callable to execute
      # @rbs isolate: bool -- Whether to expose in the isolated realm
      # @rbs return: void
      def initialize(frame, name, apply, isolate: false)
        @frame = frame
        @name = name
        @apply = apply
        @isolate = isolate
        @channel = "__puppeteer__#{@frame._id}_page_exposeFunction_#{@name}"
        @scripts = []
        @disposed = false
        @listener = nil
        @frame_listener = nil
        @injected_contexts = {}
      end

      # Check if this exposed function is disposed.
      # @rbs return: bool -- Whether disposed
      def disposed?
        @disposed
      end

      # Dispose this exposed function, removing it from the page.
      # @rbs return: void
      def dispose
        return if @disposed

        @disposed = true

        session.off("script.message", &@listener) if @listener
        @listener = nil
        if @frame_listener
          @frame.page.off(:frameattached, &@frame_listener)
          @frame_listener = nil
        end

        remove_binding_from_frame(@frame)

        @scripts.each do |frame, script_id|
          begin
            frame.browsing_context.remove_preload_script(script_id).wait
          rescue StandardError => e
            debug_error(e)
          end
        end
      end

      private

      # Set up the exposed function by injecting it into the page.
      # @rbs return: void
      def setup
        @listener = proc do |params|
          handle_message(params)
        end
        session.on("script.message", &@listener)

        @frame_listener = proc do |frame|
          inject_into_frame(frame) if frame_in_scope?(frame)
        end
        @frame.page.on(:frameattached, &@frame_listener)

        inject_into_frames
      end

      # Build the JavaScript function declaration for exposeFunction.
      # @rbs return: String -- JavaScript function declaration
      def build_function_declaration
        name_literal = JSON.generate(@name)
        <<~JS
          (callback) => {
            Object.assign(globalThis, {
              [#{name_literal}]: function (...args) {
                return new Promise((resolve, reject) => {
                  callback([resolve, reject, args]);
                });
              },
            });
          }
        JS
      end

      # Build the channel argument for script.addPreloadScript/callFunction.
      # @rbs return: Hash[Symbol, untyped]
      def channel_argument
        {
          type: "channel",
          value: {
            channel: @channel,
            ownership: "root"
          }
        }
      end

      # Inject the function into existing frames.
      # @rbs return: void
      def inject_into_frames
        frames = [@frame]
        frames.each do |frame|
          frames.concat(frame.child_frames)
          inject_into_frame(frame)
        end
      end

      # Inject the function into a single frame.
      # @rbs frame: Frame -- Frame to inject into
      # @rbs return: void
      def inject_into_frame(frame)
        return if @injected_contexts[frame.browsing_context.id]

        function_declaration = build_function_declaration
        channel = channel_argument
        realm = @isolate ? frame.isolated_realm : frame.main_realm
        script_id = nil

        if frame.browsing_context.parent.nil?
          begin
            script_id = frame.browsing_context.add_preload_script(
              function_declaration,
              arguments: [channel],
              sandbox: realm.core_realm.sandbox
            ).wait
          rescue StandardError => e
            debug_error(e)
          end
        end

        begin
          realm.core_realm.call_function(
            function_declaration,
            false,
            arguments: [channel]
          ).wait
        rescue StandardError => e
          debug_error(e)
          return
        end

        @scripts << [frame, script_id] if script_id
        @injected_contexts[frame.browsing_context.id] = true
      end

      # Handle script.message events from the page.
      # @rbs params: Hash[String, untyped] -- BiDi script.message params
      # @rbs return: void
      def handle_message(params)
        return if @disposed
        return unless params.is_a?(Hash)
        return unless params["channel"] == @channel

        source = params["source"] || {}
        frame = find_frame(source["context"])
        return unless frame

        realm = find_realm(frame, source["realm"])
        return unless realm

        data_handle = JSHandle.from(params["data"], realm.core_realm)
        begin
          process_call(data_handle)
        ensure
          begin
            data_handle.dispose
          rescue StandardError
            nil
          end
        end
      rescue StandardError => e
        debug_error(e)
      end

      # Process a function call from the page.
      # @rbs data_handle: JSHandle -- Handle with [resolve, reject, args]
      # @rbs return: void
      def process_call(data_handle)
        args = []
        handles = []
        args_handle = data_handle.evaluate_handle("([, , args]) => args")

        begin
          args_handle.get_properties.each do |index, handle|
            index_int = begin
              Integer(index, 10)
            rescue ArgumentError, TypeError
              nil
            end
            next unless index_int

            handles << handle
            if handle.is_a?(ElementHandle)
              args[index_int] = handle
            else
              args[index_int] = handle.json_value
            end
          end

          result = @apply.call(*args)
          result = AsyncUtils.await(result)
        rescue StandardError => e
          if e.is_a?(ThrownValue)
            send_thrown_value(data_handle, e.value)
          elsif e.is_a?(TypeError) && e.message.include?("exception class/object expected")
            send_thrown_value(data_handle, nil)
          else
            send_error(data_handle, e)
          end
          dispose_call_handles(args_handle, handles)
          return
        end

        send_result(data_handle, result)
        dispose_call_handles(args_handle, handles)
      end

      # Send a successful response back to the page.
      # @rbs data_handle: JSHandle -- Handle with [resolve, reject, args]
      # @rbs result: untyped -- Result value
      # @rbs return: void
      def send_result(data_handle, result)
        data_handle.evaluate(<<~JS, result)
          ([resolve], result) => {
            resolve(result);
          }
        JS
      rescue StandardError => e
        debug_error(e)
      end

      # Send an error response back to the page.
      # @rbs data_handle: JSHandle -- Handle with [resolve, reject, args]
      # @rbs error: StandardError -- Error to send
      # @rbs return: void
      def send_error(data_handle, error)
        name = error.class.name
        message = error.message
        stack = error.backtrace&.join("\n")
        data_handle.evaluate(<<~JS, name, message, stack)
          ([, reject], name, message, stack) => {
            const error = new Error(message);
            error.name = name;
            if (stack) {
              error.stack = stack;
            }
            reject(error);
          }
        JS
      rescue StandardError => e
        debug_error(e)
      end

      # Send a non-Error rejection value back to the page.
      # @rbs data_handle: JSHandle -- Handle with [resolve, reject, args]
      # @rbs value: untyped -- Value to reject with
      # @rbs return: void
      def send_thrown_value(data_handle, value)
        data_handle.evaluate(<<~JS, value)
          ([, reject], value) => {
            reject(value);
          }
        JS
      rescue StandardError => e
        debug_error(e)
      end

      # Dispose call handles after processing.
      # @rbs args_handle: JSHandle -- Args handle
      # @rbs handles: Array[JSHandle] -- Arg handles
      # @rbs return: void
      def dispose_call_handles(args_handle, handles)
        begin
          args_handle.dispose
        rescue StandardError
          nil
        end
        handles.each do |handle|
          begin
            handle.dispose
          rescue StandardError
            nil
          end
        end
      end

      # Find frame by browsing context ID.
      # @rbs context_id: String -- Browsing context ID
      # @rbs return: Frame?
      def find_frame(context_id)
        frames = [@frame]
        frames.each do |frame|
          return frame if frame.browsing_context.id == context_id
          frames.concat(frame.child_frames)
        end
        nil
      end

      # Find frame realm by realm ID.
      # @rbs frame: Frame -- Frame to search
      # @rbs realm_id: String -- Realm ID
      # @rbs return: FrameRealm?
      def find_realm(frame, realm_id)
        return frame.main_realm if frame.main_realm.core_realm.id == realm_id
        return frame.isolated_realm if frame.isolated_realm.core_realm.id == realm_id

        nil
      end

      # Check if a frame belongs to the current frame subtree.
      # @rbs frame: Frame -- Candidate frame
      # @rbs return: bool
      def frame_in_scope?(frame)
        current = frame
        while current
          return true if current == @frame
          current = current.parent_frame
        end
        false
      end

      # Remove the exposed binding from a frame subtree.
      # @rbs frame: Frame -- Root frame
      # @rbs return: void
      def remove_binding_from_frame(frame)
        begin
          frame.evaluate("(name) => { delete globalThis[name]; }", @name)
        rescue StandardError => e
          debug_error(e)
        end

        frame.child_frames.each do |child|
          remove_binding_from_frame(child)
        end
      end

      # Get the BiDi session.
      # @rbs return: Core::Session
      def session
        @frame.browsing_context.user_context.browser.session
      end

      def debug_error(error)
        return unless ENV["DEBUG_BIDI_COMMAND"]

        warn(error.full_message)
      end
    end
  end
end

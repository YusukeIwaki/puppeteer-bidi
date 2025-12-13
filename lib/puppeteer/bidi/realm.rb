# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Base realm abstraction that mirrors Puppeteer's Realm class hierarchy.
    # Provides shared lifecycle management for WaitTask instances.
    # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Realm.ts
    class Realm
      attr_reader :task_manager #: TaskManager

      # @rbs timeout_settings: TimeoutSettings -- Timeout settings
      # @rbs return: void
      def initialize(timeout_settings)
        @timeout_settings = timeout_settings
        @task_manager = TaskManager.new
        @disposed = false
      end

      # Get the environment object (must be implemented by subclass)
      # @rbs return: untyped -- Environment object
      def environment
        raise NotImplementedError, 'Subclass must expose its environment object'
      end

      # Get the page for this realm
      # @rbs return: Page -- Page instance
      def page
        env = environment
        return env.page if env.respond_to?(:page)

        raise NotImplementedError, 'Environment must expose a page reference'
      end

      # Get the default timeout
      # @rbs return: Numeric -- Default timeout in ms
      def default_timeout
        @timeout_settings.timeout
      end

      # Wait for a function to return a truthy value
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs options: Hash[Symbol, untyped] -- Wait options (timeout, polling, root)
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs &block: ((JSHandle) -> void)? -- Optional block called with result
      # @rbs return: JSHandle -- Handle to the truthy result
      def wait_for_function(page_function, options = {}, *args, &block)
        ensure_environment_active!

        polling = options[:polling] || 'raf'
        if polling.is_a?(Numeric) && polling < 0
          raise ArgumentError, "Cannot poll with non-positive interval: #{polling}"
        end

        timeout = options.key?(:timeout) ? options[:timeout] : default_timeout
        wait_task_options = {
          polling: polling,
          timeout: timeout,
          root: options[:root]
        }

        result = WaitTask.new(self, wait_task_options, page_function, *args).result

        Async(&block).wait if block

        result.wait
      end

      # Dispose this realm
      # @rbs return: void
      def dispose
        return if @disposed

        @disposed = true
        @task_manager.terminate_all(Error.new('waitForFunction failed: frame got detached.'))
      end

      # Check if this realm is disposed
      # @rbs return: bool -- Whether realm is disposed
      def disposed?
        @disposed
      end

      # Adopt a handle from another realm into this realm.
      # Mirrors Puppeteer's BidiRealm#adoptHandle implementation.
      # @rbs handle: JSHandle -- The handle to adopt
      # @rbs return: JSHandle -- Handle that belongs to this realm
      def adopt_handle(handle)
        raise ArgumentError, 'handle must be a JSHandle' unless handle.is_a?(JSHandle)

        evaluate_handle('(node) => node', handle)
      end

      # Transfer a handle into this realm, disposing of the original.
      # Mirrors Puppeteer's BidiRealm#transferHandle implementation.
      # @rbs handle: JSHandle -- Handle that may belong to another realm
      # @rbs return: JSHandle -- Handle adopted into this realm
      def transfer_handle(handle)
        raise ArgumentError, 'handle must be a JSHandle' unless handle.is_a?(JSHandle)

        return handle if handle.realm.equal?(self)

        adopted = adopt_handle(handle)
        handle.dispose
        adopted
      end

      private

      # Ensure the environment is still active
      # @rbs return: void
      def ensure_environment_active!
        env = environment
        return unless env.respond_to?(:detached?)

        raise FrameDetachedError if env.detached?
      end
    end

    # Concrete realm that wraps the default window realm for a Frame.
    # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Realm.ts
    class FrameRealm < Realm
      attr_reader :core_realm #: Core::WindowRealm

      # @rbs frame: Frame -- Frame instance
      # @rbs core_realm: Core::WindowRealm -- Core window realm
      # @rbs return: void
      def initialize(frame, core_realm)
        @frame = frame
        @core_realm = core_realm
        @puppeteer_util_handle = nil
        @puppeteer_util_lazy_arg = nil
        super(frame.page.timeout_settings)

        setup_core_realm_callbacks
      end

      # Get the frame environment
      # @rbs return: Frame -- Frame instance
      def environment
        @frame
      end

      # Get the page
      # @rbs return: Page -- Page instance
      def page
        @frame.page
      end

      # Evaluate JavaScript in this realm
      # @rbs script: String -- JavaScript code to evaluate
      # @rbs *args: untyped -- Arguments to pass to the script
      # @rbs return: untyped -- Evaluation result
      def evaluate(script, *args)
        ensure_environment_active!

        result = execute_with_core(script, args).wait
        handle_evaluation_exception(result) if result['type'] == 'exception'

        actual_result = result['result'] || result
        Deserializer.deserialize(actual_result)
      end

      # Evaluate JavaScript and return a handle to the result
      # @rbs script: String -- JavaScript code to evaluate
      # @rbs *args: untyped -- Arguments to pass to the script
      # @rbs return: JSHandle -- Handle to the result
      def evaluate_handle(script, *args)
        ensure_environment_active!

        result = execute_with_core(script, args).wait
        handle_evaluation_exception(result) if result['type'] == 'exception'

        JSHandle.from(result['result'], @core_realm)
      end

      # Call a function in the realm
      # @rbs function_declaration: String -- Function source code
      # @rbs await_promise: bool -- Whether to await promise results
      # @rbs **options: untyped -- Additional options
      # @rbs return: Hash[String, untyped] -- Evaluation result
      def call_function(function_declaration, await_promise, **options)
        ensure_environment_active!

        result = @core_realm.call_function(function_declaration, await_promise, **options).wait
        handle_evaluation_exception(result) if result['type'] == 'exception'

        result
      end

      # Get the Puppeteer utility handle
      # @rbs return: JSHandle -- Puppeteer utility handle
      def puppeteer_util
        return @puppeteer_util_handle if @puppeteer_util_handle

        script = "(function() { const module = { exports: {} }; #{PUPPETEER_INJECTED_SOURCE}; return module.exports.default; })()"
        @puppeteer_util_handle = evaluate_handle(script)
      end

      # Get or create lazy arg for Puppeteer utility
      # @rbs return: LazyArg -- Lazy argument for Puppeteer utility
      def puppeteer_util_lazy_arg
        @puppeteer_util_lazy_arg ||= LazyArg.create { puppeteer_util }
      end

      # Reset the Puppeteer utility handle
      # @rbs return: void
      def reset_puppeteer_util_handle!
        handle = @puppeteer_util_handle
        @puppeteer_util_handle = nil
        @puppeteer_util_lazy_arg = nil
        return unless handle

        begin
          handle.dispose
        rescue StandardError
          # The realm might already be gone; ignore cleanup failures.
        end
      end

      # Wait for a function to return a truthy value
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs options: Hash[Symbol, untyped] -- Wait options
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs &block: ((JSHandle) -> void)? -- Optional block called with result
      # @rbs return: JSHandle -- Handle to the truthy result
      def wait_for_function(page_function, options = {}, *args, &block)
        raise FrameDetachedError if @frame.detached?

        super
      end

      # Dispose this realm
      # @rbs return: void
      def dispose
        reset_puppeteer_util_handle!
        super
      end

      private

      # Execute script with core realm
      # @rbs script: String -- JavaScript code
      # @rbs args: Array[untyped] -- Arguments
      # @rbs return: Async::Task[Hash[String, untyped]] -- Evaluation result
      def execute_with_core(script, args)
        script_trimmed = script.strip

        is_iife = script_trimmed.match?(/\)\s*\(\s*\)\s*\z/)
        is_function = !is_iife && (
          script_trimmed.match?(/\A\s*(?:async\s+)?(?:\(.*?\)|[a-zA-Z_$][\w$]*)\s*=>/) ||
          script_trimmed.match?(/\A\s*(?:async\s+)?function\s*\w*\s*\(/)
        )

        if is_function
          serialized_args = args.map { |arg| Serializer.serialize(arg) }
          options = {}
          options[:arguments] = serialized_args unless serialized_args.empty?
          @core_realm.call_function(script_trimmed, true, **options)
        else
          @core_realm.evaluate(script_trimmed, true)
        end
      end

      # Handle evaluation exception from result
      # @rbs result: Hash[String, untyped] -- Evaluation result containing exception
      # @rbs return: void
      def handle_evaluation_exception(result)
        exception_details = result['exceptionDetails']
        return unless exception_details

        text = exception_details['text'] || 'Evaluation failed'
        exception = exception_details['exception']

        error_message = text

        if exception && exception['type'] != 'error'
          thrown_value = Deserializer.deserialize(exception)
          error_message = "Evaluation failed: #{thrown_value}"
        end

        raise error_message
      end

      # Set up core realm event callbacks
      # @rbs return: void
      def setup_core_realm_callbacks
        @core_realm.environment = @frame if @core_realm.respond_to?(:environment=)

        destroyed_listener = proc do |payload|
          reason = payload.is_a?(Hash) ? payload[:reason] : payload
          task_manager.terminate_all(Error.new(reason || 'Realm destroyed'))
          dispose
        end

        updated_listener = proc do
          reset_puppeteer_util_handle!
          task_manager.rerun_all
        end

        @core_realm.on(:destroyed, &destroyed_listener)
        @core_realm.on(:updated, &updated_listener)
      end
    end
  end
end

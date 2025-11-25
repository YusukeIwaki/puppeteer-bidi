# frozen_string_literal: true

module Puppeteer
  module Bidi
    # WaitTask orchestrates polling for a predicate using Puppeteer's Poller classes.
    # This is a faithful port of Puppeteer's WaitTask implementation:
    # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/common/WaitTask.ts
    #
    # Note: signal and AbortSignal are not implemented as they are JavaScript-specific
    class WaitTask
      # Corresponds to Puppeteer's WaitTask constructor
      # @param world [Realm] The realm to execute in (matches Puppeteer's World abstraction)
      # @param options [Hash] Options for waiting
      # @option options [String, Numeric] :polling Polling strategy ('raf', 'mutation', or interval in ms)
      # @option options [Numeric] :timeout Timeout in milliseconds
      # @option options [ElementHandle] :root Root element for mutation polling
      # @param fn [String] JavaScript function to evaluate
      # @param args [Array] Arguments to pass to the function
      def initialize(world, options, fn, *args)
        @world = world
        @polling = options[:polling]
        @root = options[:root]

        # Convert function to string format
        # Corresponds to Puppeteer's switch (typeof fn)
        if fn.is_a?(String)
          # Check if the string is already a function (starts with "function ", "(", or "async ")
          # If so, use it as-is. Otherwise, wrap it as an expression.
          if fn.strip.match?(/\A(?:function\s|\(|async\s)/)
            @fn = fn
          else
            @fn = "() => {return (#{fn});}"
          end
        else
          raise ArgumentError, 'fn must be a string'
        end
        @args = args

        # Corresponds to Puppeteer's #timeout and #timeoutError
        @timeout_task = nil
        @generic_error = StandardError.new('Waiting failed')
        @timeout_error = nil

        # Corresponds to Puppeteer's #result = Deferred.create<HandleFor<T>>()
        @result = Async::Promise.new

        # Corresponds to Puppeteer's #poller?: JSHandle<Poller<T>>
        @poller = nil

        # Track the active rerun Async task so we can cancel it when rerunning
        @rerun_task = nil

        # Validate polling interval
        if @polling.is_a?(Numeric) && @polling < 0
          raise ArgumentError, "Cannot poll with non-positive interval: #{@polling}"
        end

        # Corresponds to Puppeteer's this.#world.taskManager.add(this)
        @world.task_manager.add(self)

        # Store timeout value and start timeout task
        # Corresponds to Puppeteer's setTimeout(() => { void this.terminate(this.#timeoutError); }, options.timeout)
        default_timeout = if @world.respond_to?(:default_timeout)
                            @world.default_timeout
                          elsif @world.respond_to?(:page)
                            @world.page.default_timeout
                          end
        @timeout_ms = options.key?(:timeout) ? options[:timeout] : default_timeout
        if @timeout_ms && @timeout_ms > 0
          @timeout_error = Puppeteer::Bidi::TimeoutError.new(
            "Waiting failed: #{@timeout_ms}ms exceeded"
          )
          # Start timeout task in background
          @timeout_task = Async do |task|
            task.sleep(@timeout_ms / 1000.0)
            @timeout_task = nil # prevent stopping in terminate
            terminate(@timeout_error)
          end
        end

        # Start polling
        # Corresponds to Puppeteer's void this.rerun()
        rerun
      end

      # Get the result as a promise
      # Corresponds to Puppeteer's get result(): Promise<HandleFor<T>>
      # @return [Async::Promise] Promise that resolves to JSHandle
      def result
        @result
      end

      # Rerun the polling task
      # Corresponds to Puppeteer's async rerun(): Promise<void>
      def rerun
        # Cancel previous rerun task if one is active
        if (previous_task = @rerun_task)
          @rerun_task = nil if @rerun_task.equal?(previous_task)
          previous_task.stop
        end

        # Launch the rerun asynchronously so it can be cancelled like Puppeteer's AbortController
        @rerun_task = Async do |task|
          begin
            perform_rerun
          rescue Async::Stop
            # Rerun was cancelled; poller cleanup happens in ensure block
          ensure
            @rerun_task = nil if @rerun_task.equal?(task)
          end
        end
      end

      # Terminate the task
      # Corresponds to Puppeteer's async terminate(error?: Error): Promise<void>
      # @param error [Exception, nil] Error to reject with
      def terminate(error = nil)
        # Corresponds to Puppeteer's this.#world.taskManager.delete(this)
        @world.task_manager.delete(self)

        # Note: this.#signal?.removeEventListener('abort', this.#onAbortSignal) is skipped
        # AbortSignal is not implemented

        # Clear timeout task
        # Corresponds to Puppeteer's clearTimeout(this.#timeout)
        if @timeout_task
          @timeout_task.stop
          @timeout_task = nil
        end

        # Reject result if not finished
        # Corresponds to Puppeteer's if (error && !this.#result.finished()) { this.#result.reject(error); }
        if error && !@result.resolved?
          @result.reject(error)
        end

        # Stop and dispose poller
        # Corresponds to Puppeteer's if (this.#poller) { ... }
        if @poller
          stop_and_dispose_poller(@poller)
          @poller = nil
        end
      end

      private

      # Run a single rerun cycle. Mirrors the async rerun logic from Puppeteer.
      def perform_rerun
        poller = nil
        schedule_rerun = false

        begin
          # Create Poller instance based on polling mode
          # Corresponds to Puppeteer's switch (this.#polling)
          poller = case @polling
                   when 'raf'
                     create_raf_poller
                   when 'mutation'
                     create_mutation_poller
                   else
                     create_interval_poller
                   end

          @poller = poller

          # Start the poller
          # Corresponds to Puppeteer's await this.#poller.evaluate(poller => { void poller.start(); });
          poller.evaluate('poller => { void poller.start(); }')

          # Get the result
          # Corresponds to Puppeteer's const result = await this.#poller.evaluateHandle(poller => { return poller.result(); });
          # Note: poller.result() returns a Promise, so we need to await it
          # evaluateHandle with awaitPromise: true will wait for the Promise to resolve
          result_handle = poller.evaluate_handle('poller => { return poller.result(); }')

          # Resolve the result
          # Corresponds to Puppeteer's this.#result.resolve(result);
          @result.resolve(result_handle)

          # Terminate cleanly
          # Corresponds to Puppeteer's await this.terminate();
          terminate
        rescue Async::Stop
          # Propagate cancellation so caller can distinguish from regular errors
          raise
        rescue => error
          # Check if this is a bad error
          # Corresponds to Puppeteer's const badError = this.getBadError(error);
          bad_error = get_bad_error(error)
          if bad_error
            # Corresponds to Puppeteer's this.#genericError.cause = badError;
            @generic_error = StandardError.new(@generic_error.message)
            @generic_error.set_backtrace([bad_error.message] + bad_error.backtrace)
            # Corresponds to Puppeteer's await this.terminate(this.#genericError);
            terminate(@generic_error)
          else
            schedule_rerun = true
          end
          # If badError is nil, it's a recoverable error and we don't terminate
          # Puppeteer would rerun automatically via realm 'updated' event
        ensure
          if poller && @poller.equal?(poller)
            stop_and_dispose_poller(poller)
            @poller = nil
          end
        end

        rerun if schedule_rerun && !@result.resolved?
      end

      # Create RAFPoller instance
      # Corresponds to Puppeteer's evaluateHandle call for RAFPoller
      def create_raf_poller
        util_handle = @world.puppeteer_util

        # Corresponds to Puppeteer's evaluateHandle with LazyArg
        script = <<~JAVASCRIPT
          ({RAFPoller, createFunction}, fn, ...args) => {
            const fun = createFunction(fn);
            return new RAFPoller(() => {
              return fun(...args);
            });
          }
        JAVASCRIPT

        handle = @world.evaluate_handle(script, util_handle, @fn, *@args)
        handle
      end

      # Create MutationPoller instance
      # Corresponds to Puppeteer's evaluateHandle call for MutationPoller
      def create_mutation_poller
        util_handle = @world.puppeteer_util

        # Corresponds to Puppeteer's evaluateHandle with LazyArg
        script = <<~JAVASCRIPT
          ({MutationPoller, createFunction}, root, fn, ...args) => {
            const fun = createFunction(fn);
            return new MutationPoller(() => {
              return fun(...args);
            }, root || document);
          }
        JAVASCRIPT

        @world.evaluate_handle(script, util_handle, @root, @fn, *@args)
      end

      # Create IntervalPoller instance
      # Corresponds to Puppeteer's evaluateHandle call for IntervalPoller
      def create_interval_poller
        util_handle = @world.puppeteer_util
        interval = @polling.is_a?(Numeric) ? @polling : 100

        # Corresponds to Puppeteer's evaluateHandle with LazyArg
        script = <<~JAVASCRIPT
          ({IntervalPoller, createFunction}, ms, fn, ...args) => {
            const fun = createFunction(fn);
            return new IntervalPoller(() => {
              return fun(...args);
            }, ms);
          }
        JAVASCRIPT

        @world.evaluate_handle(script, util_handle, interval, @fn, *@args)
      end

      # Check if error should terminate task
      # Corresponds to Puppeteer's getBadError(error: unknown): Error | undefined
      # @param error [Exception] Error to check
      # @return [Exception, nil] Error if it should terminate, nil if recoverable
      def get_bad_error(error)
        return nil unless error

        error_message = error.message

        # Frame detachment is fatal
        # Corresponds to Puppeteer's error.message.includes('Execution context is not available in detached frame')
        if error_message.include?('Execution context is not available in detached frame')
          return StandardError.new('Waiting failed: Frame detached')
        end

        # These are recoverable (realm was destroyed/recreated)
        # Corresponds to Puppeteer's error.message.includes('Execution context was destroyed')
        return nil if error_message.include?('Execution context was destroyed')

        # Corresponds to Puppeteer's error.message.includes('Cannot find context with specified id')
        return nil if error_message.include?('Cannot find context with specified id')

        # Corresponds to Puppeteer's error.message.includes('DiscardedBrowsingContextError')
        return nil if error_message.include?('DiscardedBrowsingContextError')

        # Recoverable when the browsing context is torn down during navigation.
        return nil if error_message.include?('Browsing Context with id')
        return nil if error_message.include?('no such frame')

        # Happens when handles become invalid after realm/navigation changes.
        return nil if error_message.include?('Unable to find an object reference for "handle"')

        # All other errors are fatal
        # Corresponds to Puppeteer's return error;
        error
      end

      # Safely stop and dispose a poller handle, ignoring cleanup errors
      def stop_and_dispose_poller(poller)
        return unless poller

        begin
          poller.evaluate('async poller => { await poller.stop(); }')
        rescue StandardError
          # Ignore errors from stopping the poller
        end

        begin
          poller.dispose
        rescue StandardError
          # Ignore dispose errors as they are low-level cleanup
        end
      end
    end
  end
end

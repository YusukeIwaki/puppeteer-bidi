# frozen_string_literal: true

require 'securerandom'

module Puppeteer
  module Bidi
    # WaitTask orchestrates polling for a predicate in the page context.
    # It mirrors Puppeteer's WaitTask by delegating the polling mechanics to
    # requestAnimationFrame, MutationObserver, or interval timers inside the
    # browser, avoiding Ruby-side busy waiting.
    class WaitTask
      class RecoverableError < StandardError; end

      RECOVERABLE_ERROR_PATTERNS = [
        'Execution context was destroyed',
        'Cannot find context with specified id',
        'DiscardedBrowsingContextError'
      ].freeze

      FRAME_DETACHED_PATTERN = 'Execution context is not available in detached frame'
      ABORT_ERROR_MESSAGE = 'WaitTask aborted'

      WAIT_TASK_ABORT = <<~JAVASCRIPT
        (taskId, message) => {
          const registry = globalThis.__puppeteerWaitTasks;
          if (!registry) {
            return false;
          }
          const entry = registry.get(taskId);
          if (!entry) {
            return false;
          }
          entry.abort(message || '#{ABORT_ERROR_MESSAGE}');
          return true;
        }
      JAVASCRIPT

      def initialize(frame, page_function, options, args)
        @frame = frame
        unless page_function.is_a?(String)
          raise ArgumentError, 'page_function must be a string'
        end

        @page_function = page_function
        @args = args

        @polling = options.fetch(:polling, 'raf')
        @signal = options[:signal]
        @timeout = if options.key?(:timeout)
                     options[:timeout]
                   else
                     frame.page.default_timeout
                   end

        validate_timeout!
        validate_polling!
        validate_signal!

        setup_abort_listener

        @serialized_args = @args.map { |arg| Serializer.serialize(arg) }
        @task_started = false
        @pending_abort_message = nil
      end

      # Execute the wait task synchronously and return a JSHandle for the success value.
      # @return [JSHandle]
      def await
        ensure_frame_attached!
        raise_if_aborted

        deadline = compute_deadline

        loop do
          raise_if_aborted
          ensure_frame_attached!
          raise_deadline_if_needed(deadline)

          timeout_for_attempt = remaining_timeout(deadline)

          begin
            return run_wait_task(timeout_for_attempt)
          rescue RecoverableError => error
            warn "[WaitTask] Recoverable error: #{error.message}" if ENV['WAITTASK_DEBUG']
            sleep recoverable_delay
            next
          end
        end
      ensure
        cleanup_abort_listener
      end

      private

      def ensure_frame_attached!
        raise FrameDetachedError if @frame.detached?
      end

      def compute_deadline
        return nil unless @timeout && @timeout.positive?

        monotonic_now + (@timeout / 1000.0)
      end

      def remaining_timeout(deadline)
        return @timeout unless deadline

        remaining_ms = ((deadline - monotonic_now) * 1000).ceil
        raise_timeout if remaining_ms <= 0

        remaining_ms
      end

      def raise_deadline_if_needed(deadline)
        return unless deadline
        raise_timeout if monotonic_now >= deadline
      end

      def raise_timeout
        raise Puppeteer::Bidi::TimeoutError, "Waiting failed: #{@timeout}ms exceeded"
      end

      def recoverable_delay
        0.05
      end

      def validate_polling!
        return unless @polling.is_a?(Numeric)
        return if @polling.positive?

        raise ArgumentError, 'Cannot poll with non-positive interval'
      end

      def validate_timeout!
        return if @timeout.nil?
        unless @timeout.is_a?(Numeric) && @timeout >= 0
          raise ArgumentError, 'Timeout must be a non-negative number'
        end
      end

      def validate_signal!
        return unless @signal
        unless @signal.is_a?(AbortSignal)
          raise ArgumentError, 'signal must be a Puppeteer::Bidi::AbortSignal'
        end
      end

      def setup_abort_listener
        return unless @signal

        @abort_listener = proc do |reason|
          message = abort_message(reason)
          @pending_abort_message = message unless @task_started
          dispatch_abort(message) if @task_started
        end

        @signal.add_abort_listener(&@abort_listener)
      end

      def cleanup_abort_listener
        return unless @signal && @abort_listener

        @signal.remove_abort_listener(@abort_listener)
        @abort_listener = nil
      end

      def abort_message(reason)
        return ABORT_ERROR_MESSAGE unless reason

        message = if reason.respond_to?(:message)
                    reason.message
                  else
                    reason.to_s
                  end

        message = message.to_s.strip
        message.empty? ? ABORT_ERROR_MESSAGE : "#{ABORT_ERROR_MESSAGE}: #{message}"
      end

      def dispatch_abort(message)
        return unless @task_started && @current_task_id

        realm = @frame.browsing_context.default_realm
        arguments = [
          Serializer.serialize(@current_task_id),
          Serializer.serialize(message)
        ]

        realm.call_function(WAIT_TASK_ABORT, false, arguments: arguments)
      rescue Connection::ProtocolError
        # If the task already settled we can safely ignore abort signalling errors.
        nil
      end

      def raise_if_aborted
        return unless @signal&.aborted?

        message = abort_message(@signal.reason)
        raise AbortError.new(message)
      end

      def run_wait_task(timeout_ms)
        realm = @frame.browsing_context.default_realm
        predicate_source = build_predicate_source
        task_script = build_task_script(predicate_source)

        arguments = build_arguments(timeout_ms)

        @current_task_id = SecureRandom.uuid
        arguments.unshift(Serializer.serialize(@current_task_id))

        warn "[WaitTask] Starting attempt task_id=#{@current_task_id} timeout=#{timeout_ms.inspect}" if ENV['WAITTASK_DEBUG']
        @task_started = true
        if @pending_abort_message
          dispatch_abort(@pending_abort_message)
          @pending_abort_message = nil
        end

        result = realm.call_function(task_script, true, arguments: arguments)

        if result['type'] == 'exception'
          handle_wait_task_exception(result)
        end

        remote_value = result['result'] || result
        warn "[WaitTask] Resolved task_id=#{@current_task_id}" if ENV['WAITTASK_DEBUG']
        JSHandle.from(remote_value, realm)
      rescue Core::RealmDestroyedError => e
        warn "[WaitTask] Realm destroyed: #{e.message}" if ENV['WAITTASK_DEBUG']
        raise FrameDetachedError, 'Frame detached during waitForFunction' if @frame.detached?
        raise RecoverableError, e.message
      rescue Connection::ProtocolError => e
        warn "[WaitTask] Protocol error: #{e.message}" if ENV['WAITTASK_DEBUG']
        if recoverable_message?(e.message)
          raise RecoverableError, e.message
        end
        raise
      ensure
        warn "[WaitTask] Finished attempt task_id=#{@current_task_id}" if ENV['WAITTASK_DEBUG']
        @task_started = false
        @current_task_id = nil
      end

      def build_arguments(timeout_ms)
        args = []
        args << Serializer.serialize(@polling)
        args << Serializer.serialize(timeout_ms)
        args.concat(@serialized_args)
        args
      end

      def build_predicate_source
        script = @page_function.strip

        if function_source?(script)
          script
        else
          "() => (#{script})"
        end
      end

      def build_task_script(predicate_source)
        <<~JAVASCRIPT
          async function (taskId, polling, timeout, ...args) {
            const predicate = #{predicate_source};

            const cleanupCallbacks = [];
            let cleanedUp = false;

            const addCleanup = callback => {
              cleanupCallbacks.push(callback);
            };

            const cleanup = () => {
              if (cleanedUp) {
                return;
              }
              cleanedUp = true;
              while (cleanupCallbacks.length) {
                const cb = cleanupCallbacks.pop();
                try {
                  cb();
                } catch (error) {
                  // Ignore cleanup errors.
                }
              }
              const registry = globalThis.__puppeteerWaitTasks;
              if (registry) {
                registry.delete(taskId);
              }
            };

            const registry = (globalThis.__puppeteerWaitTasks ||= new Map());

            let settled = false;

            const pollPromise = new Promise((resolve, reject) => {
              const finish = value => {
                if (settled) {
                  return;
                }
                settled = true;
                cleanup();
                resolve(value);
              };

              const fail = error => {
                if (settled) {
                  return;
                }
                settled = true;
                cleanup();
                reject(error);
              };

              registry.set(taskId, {
                abort(message) {
                  const err = message instanceof Error ? message : new Error(message || '#{ABORT_ERROR_MESSAGE}');
                  fail(err);
                }
              });

              addCleanup(() => {
                if (registry.get(taskId)) {
                  registry.delete(taskId);
                }
              });

              const check = async () => {
                const result = await predicate(...args);
                if (result) {
                  finish(result);
                  return true;
                }
                return false;
              };

              const startRaf = () => {
                let rafId = null;
                const schedule = () => {
                  rafId = requestAnimationFrame(async () => {
                    if (settled) {
                      return;
                    }
                    try {
                      if (await check()) {
                        return;
                      }
                      schedule();
                    } catch (error) {
                      fail(error);
                    }
                  });
                };
                schedule();
                addCleanup(() => {
                  if (rafId !== null) {
                    cancelAnimationFrame(rafId);
                  }
                });
              };

              const startInterval = interval => {
                let timerId = null;
                const schedule = () => {
                  timerId = setTimeout(async () => {
                    if (settled) {
                      return;
                    }
                    try {
                      if (await check()) {
                        return;
                      }
                      schedule();
                    } catch (error) {
                      fail(error);
                    }
                  }, interval);
                };
                schedule();
                addCleanup(() => {
                  if (timerId !== null) {
                    clearTimeout(timerId);
                  }
                });
              };

              const startMutation = () => {
                try {
                  const observer = new MutationObserver(() => {
                    if (settled) {
                      return;
                    }
                    (async () => {
                      try {
                        await check();
                      } catch (error) {
                        fail(error);
                      }
                    })();
                  });
                  observer.observe(document, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    characterData: true
                  });
                  addCleanup(() => observer.disconnect());
                  return true;
                } catch (error) {
                  return false;
                }
              };

              (async () => {
                try {
                  if (await check()) {
                    return;
                  }
                } catch (error) {
                  fail(error);
                  return;
                }

                if (polling === 'raf') {
                  startRaf();
                } else if (polling === 'mutation') {
                  if (!startMutation()) {
                    startInterval(100);
                  }
                } else {
                  const interval = typeof polling === 'number' ? polling : 100;
                  startInterval(interval);
                }
              })();
            });

            const timeoutPromise = timeout && timeout > 0 ? new Promise((_, reject) => {
              const timeoutId = setTimeout(() => {
                reject(new Error(`Waiting failed: ${timeout}ms exceeded`));
              }, timeout);
              addCleanup(() => clearTimeout(timeoutId));
            }) : null;

            try {
              if (timeoutPromise) {
                return await Promise.race([pollPromise, timeoutPromise]);
              }
              return await pollPromise;
            } finally {
              cleanup();
            }
          }
        JAVASCRIPT
      end

      def recoverable_message?(message)
        return false unless message

        RECOVERABLE_ERROR_PATTERNS.any? { |pattern| message.include?(pattern) }
      end

      def function_source?(script)
        return false if iife?(script)
        script.match?(/\A\s*(?:async\s+)?(?:\(.*?\)|[a-zA-Z_$][\w$]*)\s*=>/) ||
          script.match?(/\A\s*(?:async\s+)?function\b/)
      end

      def iife?(script)
        script.match?(/\)\s*\(\s*\)\s*\z/)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def handle_wait_task_exception(result)
        details = result['exceptionDetails']
        message = exception_message(details)

        normalized = message&.sub(/\AError:\s*/, '')

        if normalized&.include?(FRAME_DETACHED_PATTERN)
          raise FrameDetachedError, 'Frame detached during waitForFunction'
        end

        if normalized&.start_with?('Waiting failed:')
          warn "[WaitTask] Timeout error: #{normalized}" if ENV['WAITTASK_DEBUG']
          raise Puppeteer::Bidi::TimeoutError, normalized
        end

        if normalized&.start_with?(ABORT_ERROR_MESSAGE)
          warn "[WaitTask] Abort error: #{normalized}" if ENV['WAITTASK_DEBUG']
          raise AbortError.new(normalized)
        end

        if recoverable_message?(normalized)
          warn "[WaitTask] Recoverable exception: #{normalized}" if ENV['WAITTASK_DEBUG']
          raise RecoverableError, normalized
        end

        warn "[WaitTask] Delegating exception: #{normalized}" if ENV['WAITTASK_DEBUG']
        @frame.send(:handle_evaluation_exception, result)
      end

      def exception_message(details)
        return unless details

        text = details['text'] || 'Evaluation failed'
        exception = details['exception']

        if exception && exception['type'] != 'error'
          thrown_value = Deserializer.deserialize(exception)
          "Evaluation failed: #{thrown_value}"
        else
          if exception && exception['description']
            return exception['description']
          end
          text
        end
      end
    end
  end
end

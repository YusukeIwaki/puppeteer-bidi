# frozen_string_literal: true
# rbs_inline: enabled

require "async"
require "async/actor"
require "delegate"
require "thread"

module Puppeteer
  module Bidi
    # Runs a dedicated Async reactor in a background thread and proxies calls into it.
    class ReactorRunner
      class Actor < Async::Actor::Proxy
        attr_reader :thread

        def close
          return if @queue.closed?

          @queue.close
          @thread.join unless ::Thread.current == @thread
        end

        def closed?
          @queue.closed?
        end
      end

      class Executor
        def run(&block)
          block.call
        end
      end

      class Proxy < SimpleDelegator
        # @rbs runner: ReactorRunner -- Reactor runner
        # @rbs target: untyped -- Target object to proxy
        # @rbs owns_runner: bool -- Whether to close runner on close/disconnect
        # @rbs return: void
        def initialize(runner, target, owns_runner: false)
          super(target)
          @runner = runner
          @owns_runner = owns_runner
        end

        def method_missing(name, *args, **kwargs, &block)
          if @owns_runner && @runner.closed? && close_like?(name)
            return nil
          end

          begin
            @runner.sync do
              args = args.map { |arg| @runner.unwrap(arg) }
              kwargs = kwargs.transform_values { |value| @runner.unwrap(value) }
              result = __getobj__.public_send(name, *args, **kwargs, &block)
              @runner.wrap(result)
            end
          ensure
            @runner.close if @owns_runner && close_like?(name)
          end
        end

        def respond_to_missing?(name, include_private = false)
          __getobj__.respond_to?(name, include_private) || super
        end

        def class
          __getobj__.class
        end

        def is_a?(klass)
          __getobj__.is_a?(klass)
        end

        alias kind_of? is_a?

        def instance_of?(klass)
          __getobj__.instance_of?(klass)
        end

        def ==(other)
          __getobj__ == @runner.unwrap(other)
        end

        def eql?(other)
          __getobj__.eql?(@runner.unwrap(other))
        end

        def hash
          __getobj__.hash
        end

        private

        def close_like?(name)
          name == :close || name == :disconnect
        end
      end

      # @rbs return: void
      def initialize
        @actor = Actor.new(Executor.new)
        @mutex = Thread::Mutex.new
      end

      # @rbs &block: () -> untyped
      # @rbs return: untyped
      def sync(&block)
        return block.call if runner_thread?
        raise Error, "ReactorRunner is closed" if closed?

        @mutex.synchronize { @actor.run(&block) }
      rescue ClosedQueueError
        raise Error, "ReactorRunner is closed"
      end

      # @rbs return: void
      def close
        return if closed?
        @actor.close
      end

      # @rbs return: bool
      def closed?
        @actor.closed?
      end

      # @rbs value: untyped
      # @rbs return: untyped
      def wrap(value)
        return value if value.nil? || value.is_a?(Proxy)

        if value.is_a?(Array)
          return value.map { |item| wrap(item) }
        end

        return Proxy.new(self, value) if proxyable?(value)

        value
      end

      # @rbs value: untyped
      # @rbs return: untyped
      def unwrap(value)
        case value
        when Proxy
          value.__getobj__
        when Array
          value.map { |item| unwrap(item) }
        when Hash
          value.transform_values { |item| unwrap(item) }
        else
          value
        end
      end

      private

      def runner_thread?
        Thread.current == @actor.thread
      end

      def proxyable?(value)
        return false if value.is_a?(Module) || value.is_a?(Class)

        name = value.class.name
        return false unless name&.start_with?("Puppeteer::Bidi")
        return false if name.start_with?("Puppeteer::Bidi::Core")
        return false if value.is_a?(ReactorRunner) || value.is_a?(Proxy)

        true
      end
    end
  end
end

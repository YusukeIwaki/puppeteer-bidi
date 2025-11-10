# frozen_string_literal: true

require 'async/barrier'

module Puppeteer
  module Bidi
    # Utility methods for working with Async tasks
    # Provides Promise.all and Promise.race equivalents using Async::Barrier
    module AsyncUtils
      # Wait for all async tasks to complete
      # Similar to Promise.all in JavaScript
      # @param tasks [Array<Proc>] Array of procs that will be executed as async tasks
      # @return [Array] Array of results in the same order as the input tasks
      # @raise If any task raises an exception, it will be propagated
      # @example
      #   results = AsyncUtils.promise_all(
      #     -> { sleep 0.1; "first" },
      #     -> { sleep 0.2; "second" },
      #     -> { sleep 0.05; "third" }
      #   )
      #   # => ["first", "second", "third"]
      def self.promise_all(*tasks)
        Sync do
          barrier = Async::Barrier.new
          results = Array.new(tasks.size)

          tasks.each_with_index do |task, index|
            barrier.async do
              results[index] = task.call
            end
          end

          # Wait for all tasks to complete
          barrier.wait

          results
        end
      end

      # Race multiple async tasks, returning the result of the first one to complete
      # Similar to Promise.race in JavaScript
      # @param tasks [Array<Proc>] Array of procs that will be executed as async tasks
      # @return The result of the first task to complete
      # @example
      #   result = AsyncUtils.promise_race(
      #     -> { sleep 1; "slow" },
      #     -> { sleep 0.1; "fast" }
      #   )
      #   # => "fast"
      def self.promise_race(*tasks)
        Sync do
          barrier = Async::Barrier.new
          result = nil

          begin
            tasks.each do |task|
              barrier.async do
                task.call
              end
            end

            # Wait for the first task to complete
            barrier.wait do |completed_task|
              result = completed_task.wait
              break # Stop waiting after the first task completes
            end

            result
          ensure
            # Cancel all remaining tasks
            barrier.stop
          end
        end
      end
    end
  end
end

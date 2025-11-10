# frozen_string_literal: true

require 'async/barrier'

module Puppeteer
  module Bidi
    # Utility methods for working with Async tasks
    # Provides Promise.all and Promise.race equivalents using Async::Barrier
    module AsyncUtils
      # Wait for all async tasks to complete
      # Similar to Promise.all in JavaScript
      # @param tasks [Array<Proc, Async::Promise>] Array of procs or promises
      # @return [Array] Array of results in the same order as the input tasks
      # @raise If any task raises an exception, it will be propagated
      # @example With procs
      #   results = AsyncUtils.promise_all(
      #     -> { sleep 0.1; "first" },
      #     -> { sleep 0.2; "second" },
      #     -> { sleep 0.05; "third" }
      #   )
      #   # => ["first", "second", "third"]
      # @example With promises
      #   promise1 = Async::Promise.new
      #   promise2 = Async::Promise.new
      #   Thread.new { sleep 0.1; promise1.resolve("first") }
      #   Thread.new { sleep 0.2; promise2.resolve("second") }
      #   results = AsyncUtils.promise_all(promise1, promise2)
      #   # => ["first", "second"]
      def self.promise_all(*tasks)
        Sync do
          barrier = Async::Barrier.new
          results = Array.new(tasks.size)

          tasks.each_with_index do |task, index|
            barrier.async do
              results[index] = if task.is_a?(Async::Promise)
                                 task.wait
                               else
                                 task.call
                               end
            end
          end

          # Wait for all tasks to complete
          barrier.wait

          results
        end
      end

      # Race multiple async tasks, returning the result of the first one to complete
      # Similar to Promise.race in JavaScript
      # @param tasks [Array<Proc, Async::Promise>] Array of procs or promises
      # @return The result of the first task to complete
      # @example With procs
      #   result = AsyncUtils.promise_race(
      #     -> { sleep 1; "slow" },
      #     -> { sleep 0.1; "fast" }
      #   )
      #   # => "fast"
      # @example With promises
      #   promise1 = Async::Promise.new
      #   promise2 = Async::Promise.new
      #   Thread.new { sleep 0.3; promise1.resolve("slow") }
      #   Thread.new { sleep 0.1; promise2.resolve("fast") }
      #   result = AsyncUtils.promise_race(promise1, promise2)
      #   # => "fast"
      def self.promise_race(*tasks)
        Sync do
          barrier = Async::Barrier.new
          result = nil

          begin
            tasks.each do |task|
              barrier.async do
                if task.is_a?(Async::Promise)
                  task.wait
                else
                  task.call
                end
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

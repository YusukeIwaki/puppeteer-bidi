# frozen_string_literal: true

module Puppeteer
  module Bidi
    # TaskManager tracks active WaitTask instances to enable coordinated lifecycle management
    # This is a faithful port of Puppeteer's TaskManager implementation:
    # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/common/WaitTask.ts
    class TaskManager
      def initialize
        @tasks = Set.new
      end

      # Add a task to the manager
      # Corresponds to Puppeteer's add(task: WaitTask<any>): void
      # @param task [WaitTask] Task to add
      def add(task)
        @tasks.add(task)
      end

      # Delete a task from the manager
      # Corresponds to Puppeteer's delete(task: WaitTask<any>): void
      # @param task [WaitTask] Task to delete
      def delete(task)
        @tasks.delete(task)
      end

      # Terminate all tasks with an optional error
      # Corresponds to Puppeteer's terminateAll(error?: Error): void
      # @param error [Exception, nil] Error to terminate with
      def terminate_all(error = nil)
        @tasks.each do |task|
          task.terminate(error)
        end
        @tasks.clear
      end

      # Rerun all tasks in parallel
      # Corresponds to Puppeteer's async rerunAll(): Promise<void>
      def rerun_all
        # Run all tasks in parallel using Async
        Async do |parent_task|
          tasks = @tasks.to_a.map do |task|
            parent_task.async { task.rerun }
          end

          # Wait for all tasks to complete
          tasks.each(&:wait)
        end.wait
      end
    end
  end
end

# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # TaskManager tracks active WaitTask instances to enable coordinated lifecycle management
    # This is a faithful port of Puppeteer's TaskManager implementation:
    # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/common/WaitTask.ts
    class TaskManager
      # @rbs return: void
      def initialize
        @tasks = Set.new
      end

      # Add a task to the manager
      # Corresponds to Puppeteer's add(task: WaitTask<any>): void
      # @rbs task: WaitTask -- Task to add
      # @rbs return: void
      def add(task)
        @tasks.add(task)
      end

      # Delete a task from the manager
      # Corresponds to Puppeteer's delete(task: WaitTask<any>): void
      # @rbs task: WaitTask -- Task to delete
      # @rbs return: void
      def delete(task)
        @tasks.delete(task)
      end

      # Terminate all tasks with an optional error
      # Corresponds to Puppeteer's terminateAll(error?: Error): void
      # @rbs error: Exception? -- Error to terminate with
      # @rbs return: void
      def terminate_all(error = nil)
        @tasks.each do |task|
          task.terminate(error)
        end
        @tasks.clear
      end

      # Rerun all tasks in parallel
      # Corresponds to Puppeteer's async rerunAll(): Promise<void>
      # @rbs return: void
      def rerun_all
        @tasks.each(&:rerun)
      end
    end
  end
end

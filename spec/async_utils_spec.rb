# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/puppeteer/bidi/async_utils'

RSpec.describe Puppeteer::Bidi::AsyncUtils do
  describe '.promise_all' do
    it 'waits for all tasks to complete and returns results in order' do
      start_time = Time.now

      results = described_class.promise_all(
        -> { sleep 0.1; 'first' },
        -> { sleep 0.2; 'second' },
        -> { sleep 0.05; 'third' }
      )

      elapsed = Time.now - start_time

      # All tasks should complete
      expect(results).to eq(['first', 'second', 'third'])

      # Should run in parallel (not sequential)
      # If sequential: 0.1 + 0.2 + 0.05 = 0.35s
      # If parallel: max(0.1, 0.2, 0.05) = 0.2s
      expect(elapsed).to be < 0.3
      expect(elapsed).to be >= 0.2
    end

    it 'returns results in the same order as input tasks' do
      results = described_class.promise_all(
        -> { sleep 0.2; 'slow' },
        -> { sleep 0.05; 'fast' },
        -> { sleep 0.1; 'medium' }
      )

      expect(results).to eq(['slow', 'fast', 'medium'])
    end

    it 'works with different return types' do
      results = described_class.promise_all(
        -> { 42 },
        -> { 'string' },
        -> { [1, 2, 3] },
        -> { { key: 'value' } }
      )

      expect(results).to eq([42, 'string', [1, 2, 3], { key: 'value' }])
    end

    it 'propagates exceptions from failed tasks' do
      expect do
        described_class.promise_all(
          -> { sleep 0.1; 'success' },
          -> { raise StandardError, 'Task failed' },
          -> { sleep 0.1; 'also success' }
        )
      end.to raise_error(StandardError, 'Task failed')
    end

    it 'handles empty task list' do
      results = described_class.promise_all()

      expect(results).to eq([])
    end

    it 'handles single task' do
      results = described_class.promise_all(
        -> { 'single result' }
      )

      expect(results).to eq(['single result'])
    end
  end

  describe '.promise_race' do
    it 'returns the result of the fastest task' do
      start_time = Time.now

      result = described_class.promise_race(
        -> { sleep 0.3; 'slow' },
        -> { sleep 0.1; 'fast' },
        -> { sleep 0.2; 'medium' }
      )

      elapsed = Time.now - start_time

      # Should return the fastest result
      expect(result).to eq('fast')

      # Should complete in ~0.1s (not wait for slower tasks)
      expect(elapsed).to be < 0.2
      expect(elapsed).to be >= 0.1
    end

    it 'cancels remaining tasks after first completion' do
      completed_tasks = []
      mutex = Mutex.new

      result = described_class.promise_race(
        -> {
          sleep 0.05
          mutex.synchronize { completed_tasks << 'fast' }
          'fast'
        },
        -> {
          sleep 0.5
          mutex.synchronize { completed_tasks << 'slow' }
          'slow'
        }
      )

      expect(result).to eq('fast')

      # Give a bit of time to ensure slow task doesn't complete
      sleep 0.1

      # Only the fast task should have completed
      expect(completed_tasks).to eq(['fast'])
    end

    it 'works with different return types' do
      result = described_class.promise_race(
        -> { sleep 0.2; { key: 'value' } },
        -> { sleep 0.1; 'string' },
        -> { sleep 0.3; 42 }
      )

      expect(result).to eq('string')
    end

    it 'propagates exception if the winning task fails' do
      expect do
        described_class.promise_race(
          -> { sleep 0.2; 'slow success' },
          -> { raise StandardError, 'Fast failure' },
          -> { sleep 0.3; 'slower success' }
        )
      end.to raise_error(StandardError, 'Fast failure')
    end

    it 'handles single task' do
      result = described_class.promise_race(
        -> { 'only one' }
      )

      expect(result).to eq('only one')
    end

    it 'returns first task that completes even if later tasks would fail' do
      result = described_class.promise_race(
        -> { sleep 0.05; 'success' },
        -> { sleep 0.2; raise StandardError, 'This should not be raised' }
      )

      expect(result).to eq('success')

      # Ensure no exception is raised from the canceled task
      sleep 0.3 # Wait to ensure canceled task doesn't cause issues
    end
  end
end

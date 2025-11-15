# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/puppeteer/bidi/async_utils'

RSpec.describe Puppeteer::Bidi::AsyncUtils do
  describe '.async_timeout' do
    it 'returns result when block completes before timeout' do
      task = described_class.async_timeout(200) do
        sleep 0.05
        'finished'
      end

      expect(task.wait).to eq('finished')
    end

    it 'returns result when block completes before timeout' do
      task = described_class.async_timeout(200) do
        Async do
          sleep 0.05
          'finished'
        end
      end

      expect(task.wait).to eq('finished')
    end

    it 'raises Async::TimeoutError when block exceeds timeout' do
      expect do
        described_class.async_timeout(50) do
          Async do
            sleep 0.1
            'never reached'
          end
        end.wait
      end.to raise_error(Async::TimeoutError)
    end

    it 'accepts promise as argument' do
      promise = Async::Promise.new
      Thread.new do
        sleep 0.05
        promise.resolve('from promise')
      end

      task = described_class.async_timeout(200, promise)

      expect(task.wait).to eq('from promise')
    end

    it 'passes async task to block when requested' do
      received_task = nil

      described_class.async_timeout(100) do |task|
        received_task = task
        'ok'
      end.wait

      expect(received_task).to be_a(Async::Task)
    end

    it 'passes async task to proc argument when requested' do
      received_task = nil

      described_class.async_timeout(100, ->(task) { received_task = task }).wait

      expect(received_task).to be_a(Async::Task)
    end
  end

  describe '.await_promise_all' do
    it 'waits for all tasks to complete and returns results in order' do
      start_time = Time.now

      results = described_class.await_promise_all(
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
      results = described_class.await_promise_all(
        -> { sleep 0.2; 'slow' },
        -> { sleep 0.05; 'fast' },
        -> { sleep 0.1; 'medium' }
      )

      expect(results).to eq(['slow', 'fast', 'medium'])
    end

    it 'works with different return types' do
      results = described_class.await_promise_all(
        -> { 42 },
        -> { 'string' },
        -> { [1, 2, 3] },
        -> { { key: 'value' } }
      )

      expect(results).to eq([42, 'string', [1, 2, 3], { key: 'value' }])
    end

    it 'propagates exceptions from failed tasks' do
      expect do
        described_class.await_promise_all(
          -> { sleep 0.1; 'success' },
          -> { raise StandardError, 'Task failed' },
          -> { sleep 0.1; 'also success' }
        )
      end.to raise_error(StandardError, 'Task failed')
    end

    it 'handles empty task list' do
      results = described_class.await_promise_all()

      expect(results).to eq([])
    end

    it 'handles single task' do
      results = described_class.await_promise_all(
        -> { 'single result' }
      )

      expect(results).to eq(['single result'])
    end
  end

  describe '.await_promise_race' do
    it 'returns the result of the fastest task' do
      start_time = Time.now

      result = described_class.await_promise_race(
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

      result = described_class.await_promise_race(
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
      result = described_class.await_promise_race(
        -> { sleep 0.2; { key: 'value' } },
        -> { sleep 0.1; 'string' },
        -> { sleep 0.3; 42 }
      )

      expect(result).to eq('string')
    end

    it 'propagates exception if the winning task fails' do
      expect do
        described_class.await_promise_race(
          -> { sleep 0.2; 'slow success' },
          -> { raise StandardError, 'Fast failure' },
          -> { sleep 0.3; 'slower success' }
        )
      end.to raise_error(StandardError, 'Fast failure')
    end

    it 'handles single task' do
      result = described_class.await_promise_race(
        -> { 'only one' }
      )

      expect(result).to eq('only one')
    end

    it 'returns first task that completes even if later tasks would fail' do
      result = described_class.await_promise_race(
        -> { sleep 0.05; 'success' },
        -> { sleep 0.2; raise StandardError, 'This should not be raised' }
      )

      expect(result).to eq('success')

      # Ensure no exception is raised from the canceled task
      sleep 0.3 # Wait to ensure canceled task doesn't cause issues
    end
  end

  describe 'with Async::Promise arguments' do
    describe '.await_promise_all' do
      it 'waits for all promises to resolve' do
        promise1 = Async::Promise.new
        promise2 = Async::Promise.new
        promise3 = Async::Promise.new

        # Resolve promises in background threads
        Thread.new { sleep 0.1; promise1.resolve('first') }
        Thread.new { sleep 0.2; promise2.resolve('second') }
        Thread.new { sleep 0.05; promise3.resolve('third') }

        results = described_class.await_promise_all(promise1, promise2, promise3)

        expect(results).to eq(['first', 'second', 'third'])
      end

      it 'works with mix of procs and promises' do
        promise = Async::Promise.new
        Thread.new { sleep 0.1; promise.resolve('from promise') }

        results = described_class.await_promise_all(
          -> { sleep 0.05; 'from proc' },
          promise
        )

        expect(results).to eq(['from proc', 'from promise'])
      end

      it 'propagates exceptions from failed promises' do
        promise1 = Async::Promise.new
        promise2 = Async::Promise.new

        Thread.new { sleep 0.05; promise1.resolve('success') }
        Thread.new do
          sleep 0.1
          promise2.reject(StandardError.new('Promise failed'))
        end

        expect do
          described_class.await_promise_all(promise1, promise2)
        end.to raise_error(StandardError, 'Promise failed')
      end
    end

    describe '.promise_race (returns Async::Task)' do
      it 'returns task that resolves to fastest promise result' do
        promise1 = Async::Promise.new
        promise2 = Async::Promise.new
        promise3 = Async::Promise.new

        # Resolve at different times
        Thread.new { sleep 0.3; promise1.resolve('slow') }
        Thread.new { sleep 0.1; promise2.resolve('fast') }
        Thread.new { sleep 0.2; promise3.resolve('medium') }

        task = described_class.promise_race(promise1, promise2, promise3)
        expect(task.wait).to eq('fast')
      end

      it 'works with mix of procs and promises' do
        promise = Async::Promise.new
        promise_x = Async::Promise.new
        Thread.new { sleep 0.2; promise.resolve('from promise') }
        Thread.new { sleep 0.2; promise_x.reject(StandardError.new('fail')) }

        task = described_class.promise_race(
          -> { sleep 0.1; 'from proc' },
          promise,
          promise_x,
        )

        expect(task.wait).to eq('from proc')
      end

      it 'propagates exception if winning promise fails' do
        promise1 = Async::Promise.new
        promise2 = Async::Promise.new

        Thread.new { sleep 0.2; promise1.resolve('slow success') }
        Thread.new do
          # Fast failure
          promise2.reject(StandardError.new('Fast failure'))
        end

        expect do
          described_class.promise_race(promise1, promise2).wait
        end.to raise_error(StandardError, 'Fast failure')
      end
    end

    describe '.await_promise_race (returns result directly)' do
      it 'cancels remaining promises after first completes' do
        promise1 = Async::Promise.new
        promise2 = Async::Promise.new

        completed = []
        mutex = Mutex.new

        Thread.new do
          sleep 0.05
          promise1.resolve('fast')
          mutex.synchronize { completed << 'fast' }
        end

        Thread.new do
          sleep 0.5
          begin
            promise2.resolve('slow')
            mutex.synchronize { completed << 'slow' }
          rescue StandardError
            # Promise may be canceled
          end
        end

        result = described_class.await_promise_race(promise1, promise2)

        expect(result).to eq('fast')

        # Give a bit of time
        sleep 0.1

        # Only fast promise should have completed
        expect(completed).to eq(['fast'])
      end
    end
  end
end

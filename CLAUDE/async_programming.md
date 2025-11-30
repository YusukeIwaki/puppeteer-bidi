# Async Programming with socketry/async

This project uses the [socketry/async](https://github.com/socketry/async) library for asynchronous operations.

## Why Async Instead of concurrent-ruby?

**IMPORTANT**: This project uses `Async` (Fiber-based), **NOT** `concurrent-ruby` (Thread-based).

| Feature               | Async (Fiber-based)                                    | concurrent-ruby (Thread-based)         |
| --------------------- | ------------------------------------------------------ | -------------------------------------- |
| **Concurrency Model** | Cooperative multitasking (like JavaScript async/await) | Preemptive multitasking                |
| **Race Conditions**   | Not possible within a Fiber                            | Requires Mutex, locks, etc.            |
| **Synchronization**   | Not needed (cooperative)                               | Required (Mutex, Semaphore)            |
| **Mental Model**      | Similar to JavaScript async/await                      | Traditional thread programming         |
| **Bug Risk**          | Lower (no race conditions)                             | Higher (race conditions, deadlocks)    |

**Key advantages:**

- **No race conditions**: Fibers yield control cooperatively, so no concurrent access to shared state
- **No Mutex needed**: Since there are no race conditions, no synchronization primitives required
- **Similar to JavaScript**: If you understand `async/await` in JavaScript, you understand Async in Ruby
- **Easier to reason about**: Code executes sequentially within a Fiber until it explicitly yields

**Example:**

```ruby
# DON'T: Use concurrent-ruby (Thread-based, requires Mutex)
require 'concurrent'
@pending = Concurrent::Map.new  # Thread-safe map
promise = Concurrent::Promises.resolvable_future
promise.fulfill(value)

# DO: Use Async (Fiber-based, no synchronization needed)
require 'async/promise'
@pending = {}  # Plain Hash is safe with Fibers
promise = Async::Promise.new
promise.resolve(value)
```

## Best Practices

1. **Use `Sync` at top level**: When running async code at the top level of a thread or application, use `Sync { }` instead of `Async { }`

   ```ruby
   Thread.new do
     Sync do
       # async operations here
     end
   end
   ```

2. **Reactor lifecycle**: The reactor is automatically managed by `Sync { }`. No need to create explicit `Async::Reactor` instances in application code.

3. **Background operations**: For long-running background tasks (like WebSocket connections), wrap `Sync { }` in a Thread:

   ```ruby
   connection_task = Thread.new do
     Sync do
       transport.connect  # Async operation that blocks until connection closes
     end
   end
   ```

4. **Promise usage**: Use `Async::Promise` for async coordination:

   ```ruby
   promise = Async::Promise.new

   # Resolve the promise
   promise.resolve(value)

   # Wait for the promise with timeout
   Async do |task|
     task.with_timeout(5) do
       result = promise.wait
     end
   end.wait
   ```

5. **No Mutex needed**: Since Async is Fiber-based, you don't need Mutex for shared state within the same event loop

## AsyncUtils: Promise.all and Promise.race

The `lib/puppeteer/bidi/async_utils.rb` module provides JavaScript-like Promise utilities:

```ruby
# Promise.all - Wait for all tasks to complete
results = AsyncUtils.promise_all(
  -> { sleep 0.1; 'first' },
  -> { sleep 0.2; 'second' },
  -> { sleep 0.05; 'third' }
)
# => ['first', 'second', 'third'] (in order, runs in parallel)

# Promise.race - Return the first to complete
result = AsyncUtils.promise_race(
  -> { sleep 0.3; 'slow' },
  -> { sleep 0.1; 'fast' },
  -> { sleep 0.2; 'medium' }
)
# => 'fast' (cancels remaining tasks)
```

**When to use AsyncUtils:**

- **Parallel task execution**: Running multiple independent async operations
- **Racing timeouts**: First of multiple operations to complete
- **NOT for event-driven waiting**: Use `Async::Promise` directly for event listeners

## WebSocket Message Handling Pattern

**CRITICAL**: BiDi message handling must use `Async do` to process messages asynchronously:

```ruby
# lib/puppeteer/bidi/transport.rb
while (message = connection.read)
  next if message.nil?

  # DO: Use Async do for non-blocking message processing
  Async do
    data = JSON.parse(message)
    debug_print_receive(data)
    @on_message&.call(data)
  rescue StandardError => e
    # Handle errors
  end
end
```

**Why this matters:**

- **Without `Async do`**: Message processing blocks the message loop, preventing other messages from being read
- **With `Async do`**: Each message is processed in a separate fiber, allowing concurrent message handling
- **Prevents deadlocks**: When multiple operations are waiting for responses, they can all be processed concurrently

**Example of the problem this solves:**

```ruby
# Without Async do:
# 1. Message A arrives and starts processing
# 2. Processing A calls wait_for_navigation which waits for Message B
# 3. Message B arrives but can't be read because Message A is still being processed
# 4. DEADLOCK

# With Async do:
# 1. Message A arrives and starts processing in Fiber 1
# 2. Fiber 1 yields when calling wait (cooperative multitasking)
# 3. Message B can now be read and processed in Fiber 2
# 4. Both messages complete successfully
```

This pattern is essential for the BiDi protocol's bidirectional communication model.

## References

- [Async Best Practices](https://socketry.github.io/async/guides/best-practices/)
- [Async Documentation](https://socketry.github.io/async/)
- [Async::Barrier Guide](https://socketry.github.io/async/guides/tasks/index.html)

# Async Programming with socketry/async

This project uses the [socketry/async](https://github.com/socketry/async) library for asynchronous operations.

## Why Async Instead of concurrent-ruby?

**IMPORTANT**: This project uses `Async` (Fiber-based), **NOT** `concurrent-ruby` (Thread-based).

| Feature               | Async (Fiber-based)                                    | concurrent-ruby (Thread-based)         |
| --------------------- | ------------------------------------------------------ | -------------------------------------- |
| **Concurrency Model** | Cooperative multitasking (like JavaScript async/await) | Preemptive multitasking                |
| **Race Conditions**   | Possible across waits, I/O, and other yield points      | Possible across thread interleavings   |
| **Synchronization**   | Async-compatible coordination for shared operations    | Thread-safe coordination as needed     |
| **Mental Model**      | Similar to JavaScript async/await                      | Traditional thread programming         |

**Key advantages:**

- **Similar to JavaScript**: If you understand `async/await` in JavaScript, you understand Async in Ruby
- **Cooperative scheduling**: Other fibers on the same reactor do not interleave within a non-yielding segment.
  A helper call can yield internally, so inspect the whole operation rather than just explicit `.wait` calls.

**Example:**

```ruby
# DON'T: Use concurrent-ruby (Thread-based, requires Mutex)
require 'concurrent'
@pending = Concurrent::Map.new  # Thread-safe map
promise = Concurrent::Promises.resolvable_future
promise.fulfill(value)

# DO: Use Async primitives and coordinate operations that can yield
require 'async/promise'
@pending = {}  # Reactor-local storage; multi-step operations can still race across yields
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

5. **Coordinate shared operations**: Use Async-compatible guards, semaphores, or a shared in-flight task/promise
   as appropriate. Do not remove an upstream guard because Ruby uses Fibers. Cross-thread access, including the
   `ReactorRunner` boundary, also needs its own thread-safety analysis.

## Lifecycle and Event Ordering

An operation can yield after marking itself as started but before cleanup or output has finished. A second caller
can observe that flag and return too early. For example, an idempotent `stop` must preserve upstream's completion
contract for concurrent callers; `@stopped = true` before a wait is not equivalent to serialized completion.

For affected APIs, preserve and test:

- The distinction between started, in-flight, completed, failed, and disposed states. Concurrent callers must wait
  or return according to upstream semantics, and receive the appropriate result or error.
- Listener registration before sending a command that can trigger the event, plus handling for events that have
  already happened and for out-of-order command responses and event handlers.
- Cancellation and error cleanup: remove listeners, stop background tasks, and settle waiters when commands fail,
  the target closes, or the operation times out. A happy-path event is not guaranteed to arrive.
- Both successful completion and failure while another caller is waiting. Coordinate test tasks to force the
  interleaving under test; sequential calls alone cannot verify a concurrency guard.

Keep coordination compatible with the reactor and avoid blocking its progress while waiting for another fiber.

## AsyncUtils: Promise.all and Promise.race

The `lib/puppeteer/bidi/async_utils.rb` module provides JavaScript-like Promise utilities:

```ruby
# Promise.all - Wait for all tasks to complete
results = AsyncUtils.promise_all(
  -> { sleep 0.1; 'first' },
  -> { sleep 0.2; 'second' },
  -> { sleep 0.05; 'third' }
).wait
# => ['first', 'second', 'third'] (in order, runs in parallel)

# Promise.race - Return the first to complete
result = AsyncUtils.promise_race(
  -> { sleep 0.3; 'slow' },
  -> { sleep 0.1; 'fast' },
  -> { sleep 0.2; 'medium' }
).wait
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

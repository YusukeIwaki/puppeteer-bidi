# ReactorRunner - Using Browser Outside Sync Blocks

## Problem

The socketry/async library requires all async operations to run inside a `Sync do ... end` block. However, some use cases cannot wrap their entire code in a Sync block:

```ruby
# This pattern doesn't work with plain async:
browser = Puppeteer::Bidi.launch_browser_instance(headless: true)
at_exit { browser.close }  # Called outside any Sync block!

Sync do
  page = browser.new_page
  page.goto("https://example.com")
end
```

The `at_exit` hook runs after the Sync block has finished, so `browser.close` would fail.

## Solution: ReactorRunner

`ReactorRunner` creates a dedicated Async reactor in a background thread and provides a way to execute code within that reactor from any thread.

### How It Works

1. **Background Thread with Reactor**: ReactorRunner spawns a new thread that runs `Sync do ... end` with a `Thread::Queue` for receiving jobs
2. **Proxy Pattern**: Returns a `Proxy` object that wraps the real Browser and forwards all method calls through the ReactorRunner
3. **Automatic Detection**: `launch_browser_instance` and `connect_to_browser_instance` check `Async::Task.current` to decide whether to use ReactorRunner

### Architecture

```
Main Thread                     Background Thread (ReactorRunner)
    │                                    │
    │  launch_browser_instance()         │
    │  ─────────────────────────────────>│ Sync do
    │                                    │   Browser.launch()
    │  <─────────────────────────────────│   (browser created)
    │  returns Proxy                     │
    │                                    │
    │  proxy.new_page()                  │
    │  ─────────────────────────────────>│   browser.new_page()
    │  <─────────────────────────────────│   (returns page)
    │                                    │
    │  at_exit { proxy.close }           │
    │  ─────────────────────────────────>│   browser.close()
    │                                    │ end
    │                                    │
```

### Key Components

#### ReactorRunner

- Creates background thread with `Sync` reactor
- Uses `Thread::Queue` to receive jobs from other threads
- `sync(&block)` method executes block in reactor and returns result
- Handles proper cleanup when closed
- Ensures thread cleanup with an `ObjectSpace` finalizer if users forget to close

#### ReactorRunner::Proxy

- Extends `SimpleDelegator` for transparent method forwarding
- Wraps/unwraps return values (e.g., Page becomes Proxy too)
- `owns_runner: true` means closing browser also closes the ReactorRunner
- Handles edge cases like calling `close` after runner is already closed

### Usage Patterns

#### Pattern 1: Block-based (Recommended)

```ruby
Puppeteer::Bidi.launch do |browser|
  page = browser.new_page
  # ... use browser
end  # automatically closed
```

#### Pattern 2: Instance with at_exit

```ruby
browser = Puppeteer::Bidi.launch_browser_instance(headless: true)
at_exit { browser.close }

Sync do
  page = browser.new_page
  page.goto("https://example.com")
end
```

#### Pattern 3: Inside existing Async context

```ruby
Sync do
  # No ReactorRunner used - browser is returned directly
  browser = Puppeteer::Bidi.launch_browser_instance(headless: true)
  page = browser.new_page
  # ...
  browser.close
end
```

### Implementation Notes

1. **Thread Safety**: `Async::Queue` handles cross-thread communication safely
2. **Proxyable Check**: Only `Puppeteer::Bidi::*` objects (excluding Core layer) are wrapped in Proxy
3. **Error Handling**: Errors in reactor are propagated back to calling thread via `Async::Promise`
4. **Type Annotations**: Return type is `Browser` (Proxy is an internal detail)

### Reference

This pattern is inspired by [async-webdriver](https://github.com/socketry/async-webdriver) by Samuel Williams (author of socketry/async).

# Navigation Waiting Pattern

This document explains the implementation of `Page.waitForNavigation` and `Frame.waitForNavigation`.

## Overview

Navigation waiting is a critical feature for browser automation. It allows you to execute an action that triggers navigation and wait for it to complete before proceeding.

## API Design

### Block-Based API

Following Ruby conventions, we provide a block-based API that hides Async complexity:

```ruby
# Wait for navigation triggered by block
page.wait_for_navigation(timeout: 30000, wait_until: 'load') do
  page.click('a')
end

# Without block - waits for any navigation
page.wait_for_navigation(timeout: 30000)
```

**Parameters:**
- `timeout` (milliseconds): Navigation timeout (default: 30000)
- `wait_until`: When to consider navigation succeeded
  - `'load'`: Wait for `load` event (default)
  - `'domcontentloaded'`: Wait for `DOMContentLoaded` event

**Returns:**
- `HTTPResponse` object for full page navigation
- `nil` for fragment navigation (#hash) or History API operations

## Navigation Types

WebDriver BiDi distinguishes three types of navigation:

### 1. Full Page Navigation

**Trigger**: `page.goto()`, clicking links, form submission

**BiDi Events:**
1. `browsingContext.navigationStarted` - Creates Navigation object
2. `browsingContext.load` or `browsingContext.domContentLoaded`

**Response**: Returns HTTPResponse object

```ruby
response = page.wait_for_navigation do
  page.evaluate("url => { window.location.href = url }", "https://example.com")
end
# => HTTPResponse object
```

### 2. Fragment Navigation

**Trigger**: Anchor link clicks (`<a href="#section">`), hash changes

**BiDi Events:**
- `browsingContext.fragmentNavigated` (no navigationStarted)

**Response**: Returns `nil`

```ruby
response = page.wait_for_navigation do
  page.click('a[href="#foobar"]')
end
# => nil
expect(page.url).to end_with('#foobar')
```

### 3. History API Navigation

**Trigger**: `history.pushState()`, `history.replaceState()`, `history.back()`, `history.forward()`

**BiDi Events:**
- `browsingContext.historyUpdated` (no navigationStarted)

**Response**: Returns `nil`

```ruby
response = page.wait_for_navigation do
  page.evaluate("() => { history.pushState({}, '', 'new.html') }")
end
# => nil
expect(page.url).to end_with('new.html')
```

## Implementation Pattern

### Event-Driven Waiting

The implementation uses an **event-driven pattern** with `Async::Promise`:

```ruby
def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
  # Single promise that all event listeners resolve
  promise = Async::Promise.new

  # Register listeners for all 3 navigation types
  navigation_listener = proc { ... promise.resolve(...) }
  history_listener = proc { ... promise.resolve(nil) }
  fragment_listener = proc { ... promise.resolve(nil) }

  @browsing_context.on(:navigation, &navigation_listener)
  @browsing_context.on(:history_updated, &history_listener)
  @browsing_context.on(:fragment_navigated, &fragment_listener)

  begin
    block.call if block  # Trigger navigation

    Async do |task|
      task.with_timeout(timeout / 1000.0) do
        promise.wait  # Wait for any listener to resolve
      end
    end.wait
  ensure
    # Clean up ALL listeners
    @browsing_context.off(:navigation, &navigation_listener)
    @browsing_context.off(:history_updated, &history_listener)
    @browsing_context.off(:fragment_navigated, &fragment_listener)
  end
end
```

### Why Not Use `AsyncUtils.promise_race`?

**TL;DR**: Event-driven waiting is different from racing independent tasks.

`AsyncUtils.promise_race` is designed for **parallel task execution**:
```ruby
# ✅ Good use case: Racing independent tasks
result = AsyncUtils.promise_race(
  -> { fetch_from_api_1 },
  -> { fetch_from_api_2 },
  -> { fetch_from_api_3 }
)
```

Navigation waiting requires **event listener coordination**:
- Need to register listeners *before* triggering navigation
- Must clean up *all* listeners regardless of which fires
- Share state between listeners (e.g., `navigation_received` flag)
- Nested event handling (Navigation object events)

The current pattern is **simpler and more appropriate** because:
1. ✅ Single promise resolved by multiple listeners
2. ✅ Clear cleanup path for all listeners in `ensure` block
3. ✅ No nested reactor issues (promise_race uses `Sync do`)
4. ✅ Handles complex nested events (Navigation object completion events)
5. ✅ Easy to debug and reason about

## Navigation Object Integration

For full page navigation, BiDi creates a Navigation object that tracks completion:

```ruby
navigation_listener = proc do |data|
  navigation = data[:navigation]
  navigation_received = true

  # Listen for Navigation completion events
  navigation.once(:fragment) { promise.resolve(nil) }
  navigation.once(:failed) { promise.resolve(nil) }
  navigation.once(:aborted) { promise.resolve(nil) }

  # Also wait for load event
  @browsing_context.once(load_event) do
    promise.resolve(response_holder[:value])
  end
end
```

This nested event handling is a key reason why `promise_race` doesn't simplify the implementation.

## Race Condition Prevention

The implementation prevents race conditions where multiple navigation types could fire:

```ruby
navigation_received = false

navigation_listener = proc do |data|
  navigation_received = true
  # ... set up Navigation object listeners
end

history_listener = proc do
  # Only resolve if we haven't received navigation event
  promise.resolve(nil) unless navigation_received || promise.resolved?
end

fragment_listener = proc do
  # Only resolve if we haven't received navigation event
  promise.resolve(nil) unless navigation_received || promise.resolved?
end
```

This ensures:
- Full page navigation takes precedence over history/fragment events
- No double-resolution of the promise
- Correct return value (HTTPResponse vs nil)

## Error Handling

Navigation can fail or timeout:

```ruby
begin
  # ... wait for navigation
rescue Async::TimeoutError
  raise Puppeteer::Bidi::TimeoutError,
        "Navigation timeout of #{timeout}ms exceeded"
end
```

## Testing

See `spec/integration/navigation_spec.rb` for comprehensive tests covering:
1. Full page navigation
2. Fragment navigation (anchor links)
3. History API - pushState
4. History API - replaceState
5. History API - back/forward

All tests verify both the navigation completes and the URL updates correctly.

## References

- [Puppeteer Frame.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Frame.ts)
- [Puppeteer BrowsingContext.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/core/BrowsingContext.ts)
- [Puppeteer Navigation.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/core/Navigation.ts)
- [WebDriver BiDi Specification](https://w3c.github.io/webdriver-bidi/#module-browsingContext)

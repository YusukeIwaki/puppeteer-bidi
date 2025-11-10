# Test Server Dynamic Routes

This document describes the dynamic route handling functionality added to the test server infrastructure.

## Overview

The test server (`spec/support/test_server.rb`) has been extended to support dynamic route interception and request synchronization, matching Puppeteer's test server capabilities.

## Features

### 1. Dynamic Route Interception

**Purpose**: Intercept specific routes and control the response timing/content.

**API:**
```ruby
server.set_route(path) do |request, response|
  # Control when/how to respond
  response_holder[:response] = response
end
```

**Usage Example:**
```ruby
it 'should intercept CSS loading' do
  with_test_state do |page:, server:, **|
    response_holder = {}

    # Intercept CSS file to control when it loads
    server.set_route('/one-style.css') do |_req, res|
      response_holder[:response] = res
    end

    # Navigate to page (will wait for CSS)
    page.goto("#{server.prefix}/one-style.html", wait: 'none')

    # Do something while CSS is pending...

    # Release the CSS response
    response_holder[:response].finish
  end
end
```

### 2. Request Synchronization

**Purpose**: Wait for a specific request to arrive at the server before proceeding.

**API:**
```ruby
# Returns an Async task that resolves when request is received
task = server.wait_for_request(path)
task.wait  # Block until request arrives (with 5s timeout)
```

**Usage Example:**
```ruby
it 'should wait for image request' do
  with_test_state do |page:, server:, **|
    # Start navigation
    page.goto("#{server.prefix}/page-with-image.html", wait: 'none')

    # Wait for the image to be requested
    begin
      server.wait_for_request('/image.png').wait
      puts "Image was requested!"
    rescue Async::TimeoutError
      puts "Image request never arrived"
    end
  end
end
```

## Implementation Details

### Class Variables

The `App` class uses class-level accessors to store routes and promises:

```ruby
class App < Sinatra::Base
  class << self
    attr_accessor :dynamic_routes, :request_promises
  end

  # Initialize class variables
  self.dynamic_routes = {}
  self.request_promises = {}
end
```

### Route Handler

All requests pass through a wildcard handler that checks for dynamic routes:

```ruby
get '*' do
  path = request.path_info
  if App.dynamic_routes[path]
    # Execute custom handler
    App.dynamic_routes[path].call(request, response)

    # Resolve promise if someone is waiting for this request
    if App.request_promises[path]
      promise = App.request_promises[path]
      App.request_promises.delete(path)
      promise.resolve(request)
    end

    halt response.status
  else
    pass  # Continue to static file serving
  end
end
```

## Testing Navigation Events

### Puppeteer Test Pattern

A common Puppeteer test pattern tests the timing of `domcontentloaded` vs `load` events:

```typescript
it('should work with both domcontentloaded and load', async () => {
  let response!: ServerResponse;
  server.setRoute('/one-style.css', (_req, res) => {
    return (response = res);
  });

  let bothFired = false;

  const navigationPromise = page.goto(server.PREFIX + '/one-style.html');
  const domContentLoadedPromise = page.waitForNavigation({ waitUntil: 'domcontentloaded' });
  const loadFiredPromise = page.waitForNavigation({ waitUntil: 'load' })
    .then(() => { bothFired = true; });

  await server.waitForRequest('/one-style.css');
  await domContentLoadedPromise;
  expect(bothFired).toBe(false);  // load hasn't fired yet

  response.end();  // Release CSS
  await loadFiredPromise;  // Now load fires
});
```

## Known Limitations and Challenges

### 1. Navigation Timing Coordination

**Challenge**: Testing `domcontentloaded` vs `load` timing requires careful coordination of:
- Navigation start (must not wait for load)
- Event listeners (must be registered before events fire)
- Resource loading (must control when resources complete)

**Issue**: In Ruby implementation, using `page.goto()` causes problems because:
- `goto(url)` internally calls `navigate(url, wait: 'complete')` by default
- This blocks until the `load` event fires
- Cannot register `wait_for_navigation` listeners after navigation completes

**Attempted Solutions:**

1. **Using `wait: 'none'`**:
   ```ruby
   page.browsing_context.navigate(url, wait: 'none')
   ```
   - Doesn't block on navigation
   - But bypasses high-level `Page` API
   - Still has timing issues with event listener registration

2. **Parallel Async tasks**:
   ```ruby
   navigation_task = Async { page.goto(url) }
   dom_loaded_task = Async { page.wait_for_navigation(wait_until: 'domcontentloaded') }
   load_task = Async { page.wait_for_navigation(wait_until: 'load') }
   ```
   - Race condition: `wait_for_navigation` might miss events if called after navigation completes
   - Async task scheduling order is not guaranteed

### 2. Request Promise Resolution

**Issue**: `server.wait_for_request()` timeout errors are logged as warnings:

```
Async::TimeoutError: execution expired
```

This is expected behavior when the request arrives immediately (before `wait_for_request` is called), but the warning is noisy.

**Current Workaround:**
```ruby
begin
  server.wait_for_request('/one-style.css').wait
rescue Async::TimeoutError
  # Request might have already arrived - ignore
end
```

### 3. Response Object API

**Limitation**: WEBrick's response object API differs from Node.js:

- **Node.js**: `response.end()` - sends response and closes connection
- **WEBrick**: `response.finish` - completes response

Must use WEBrick-specific methods in route handlers.

## Future Improvements

### 1. Navigation API Enhancement

Consider adding a `Page.navigate` method that exposes the `wait` parameter:

```ruby
# High-level API with wait control
page.navigate(url, wait: 'none')  # Start navigation without waiting
page.navigate(url, wait: 'interactive')  # Wait for domcontentloaded
page.navigate(url, wait: 'complete')  # Wait for load (default)
```

### 2. Event Listener Preregistration

Add API to register navigation listeners before starting navigation:

```ruby
page.with_navigation_listeners do |listeners|
  listeners.on_dom_content_loaded { puts "DOM ready" }
  listeners.on_load { puts "Page loaded" }

  page.goto(url)  # Listeners already registered
end
```

### 3. Test Server Request Queue

Store all incoming requests in a queue for post-facto checking:

```ruby
# Record all requests
server.enable_request_recording

page.goto(url)

# Check what was requested
requests = server.recorded_requests
expect(requests.map(&:path)).to include('/one-style.css')
```

## Related Files

- `spec/support/test_server.rb` - Test server implementation
- `spec/integration/navigation_spec.rb` - Navigation tests using dynamic routes
- `spec/assets/one-style.html` - Test asset with external CSS
- `spec/assets/one-style.css` - CSS file for testing resource loading

## References

- [Puppeteer test server](https://github.com/puppeteer/puppeteer/blob/main/test/src/server/index.ts)
- [Puppeteer navigation tests](https://github.com/puppeteer/puppeteer/blob/main/test/src/navigation.spec.ts)
- [WEBrick Response API](https://ruby-doc.org/stdlib-3.0.0/libdoc/webrick/rdoc/WEBrick/HTTPResponse.html)

# Puppeteer-BiDi Development Guide

This document outlines the design philosophy, architecture, and implementation guidelines for the puppeteer-bidi gem.

## Project Overview

### Purpose

Port the WebDriver BiDi protocol portions of Puppeteer to Ruby, providing a standards-based tool for Firefox automation.

### Comparison with Existing Tools

| Gem                           | Protocol                       | Target Browser    | Features                       |
| ----------------------------- | ------------------------------ | ----------------- | ------------------------------ |
| **puppeteer-ruby**            | CDP (Chrome DevTools Protocol) | Chrome/Chromium   | Chrome-specific, full-featured |
| **puppeteer-bidi** (this gem) | WebDriver BiDi                 | Firefox (primary) | W3C standard, cross-browser    |

### Development Principles

- **BiDi-only**: Do not port CDP protocol-related code
- **Standards compliance**: Adhere to W3C WebDriver BiDi specification
- **Firefox optimization**: Maximize BiDi protocol capabilities
- **Ruby conventions**: Design Ruby-idiomatic interfaces

## Understanding Puppeteer's Architecture

### Hierarchical Object Model

Puppeteer adopts an intuitive API design that mirrors browser structure:

```
Browser
├── BrowserContext (isolated sessions)
│   └── Page (tabs/windows)
│       ├── Frame (main/iframes)
│       │   ├── ExecutionContext
│       │   └── ElementHandle/JSHandle
│       └── NetworkManager
```

#### Key Components

| Component          | Role                     | Creation Method                              |
| ------------------ | ------------------------ | -------------------------------------------- |
| **Browser**        | Entire browser instance  | `puppeteer.launch()` / `puppeteer.connect()` |
| **BrowserContext** | Isolated user session    | `browser.createIncognitoBrowserContext()`    |
| **Page**           | Single tab/popup         | `context.newPage()`                          |
| **Frame**          | Frame within page        | Auto-generated (iframe/frame tags)           |
| **ElementHandle**  | Reference to DOM element | `page.$()` / `page.$$()`                     |

### Three-Layer Architecture

```
┌─────────────────────────────────┐
│  Upper Layer                    │
│  Puppeteer API & Browser        │
│  (High-level API, user-facing)  │
├─────────────────────────────────┤
│  Middle Layer                   │
│  Communication Protocol (BiDi)  │
│  (WebSocket, commands/events)   │
├─────────────────────────────────┤
│  Base Layer                     │
│  Ruby Environment               │
│  (WebSocket client, JSON)       │
└─────────────────────────────────┘
```

## WebDriver BiDi Protocol

### Characteristics

- **Communication**: WebSocket (bidirectional)
- **Message format**: JSON-RPC compliant
- **Standardization**: W3C standard specification
- **Browser support**: Firefox, Chrome, Edge (in progress)

### Communication Flow

#### Command Sending

```json
{
  "id": 1,
  "method": "browsingContext.navigate",
  "params": {
    "context": "context-id",
    "url": "https://example.com"
  }
}
```

#### Response Receiving

```json
{
  "id": 1,
  "result": {
    "navigation": "navigation-id",
    "url": "https://example.com"
  }
}
```

#### Event Receiving

```json
{
  "method": "browsingContext.navigationStarted",
  "params": {
    "context": "context-id",
    "navigation": "navigation-id",
    "url": "https://example.com"
  }
}
```

### Protocol Comparison

| Feature                 | CDP                       | WebDriver BiDi            |
| ----------------------- | ------------------------- | ------------------------- |
| **Communication Model** | Bidirectional (WebSocket) | Bidirectional (WebSocket) |
| **Standardization**     | Non-standard (Google)     | W3C standard              |
| **Browser Support**     | Chromium only             | All browsers              |
| **API Stability**       | Low (frequent changes)    | High (standardized)       |

## Implementation Guidelines

### Essential Components

#### 1. Protocol Layer

- **WebSocket communication**: Connection management with BiDi server
- **Command sending**: Method invocation and response waiting
- **Event handling**: Subscription and processing of async events
- **Session management**: Connection state management

#### 2. Core API

- **Browser**: Browser instance management
- **BrowserContext**: Isolated browsing contexts
- **Page**: Core of page operations
- **Frame**: Frame management

#### 3. State Management

- **FrameManager**: Frame tree tracking

  - `browsingContext.contextCreated`
  - `browsingContext.contextDestroyed`
  - `browsingContext.navigationStarted`

- **NetworkManager**: Network activity monitoring
  - `network.beforeRequestSent`
  - `network.responseCompleted`
  - `network.fetchError`

### Anatomy of API Calls

#### Navigation Example

```ruby
page.goto('https://example.com', wait_until: 'networkidle')
```

Internal processing flow:

1. **Issue command**: `browsingContext.navigate`
2. **Subscribe to events**: NavigationManager monitors events
3. **Track state**: NetworkManager tracks requests
4. **Check conditions**: Determine `networkidle` condition
5. **Resolve promise**: Complete when condition is satisfied

#### Click Example

```ruby
page.click(selector)
```

Internal processing flow:

1. **Find element**: Execute selector via `script.evaluate`
2. **Check preconditions**: Verify visibility and validity
3. **Scroll**: Scroll element into viewport if needed
4. **Calculate coordinates**: Get element position and size
5. **Send events**: Simulate click via `input.performActions`

### Major BiDi Modules

| Module            | Role                 | Key Methods                    |
| ----------------- | -------------------- | ------------------------------ |
| `browsingContext` | Context management   | navigate, create, close        |
| `script`          | JavaScript execution | evaluate, callFunction         |
| `input`           | User input           | performActions, releaseActions |
| `network`         | Network              | addIntercept, continueRequest  |
| `session`         | Session management   | subscribe, unsubscribe         |

## Core Layer Architecture

The `lib/puppeteer/bidi/core/` module provides a structured, object-oriented abstraction over the WebDriver BiDi protocol.

### Design Philosophy

The Core layer follows Puppeteer's BiDi core design principles:

1. **Required vs Optional Arguments**: Required arguments are method parameters, optional ones are keyword arguments
2. **Session Visibility**: Session is never exposed on public APIs except Browser
3. **Spec Compliance**: Strictly follows WebDriver BiDi specification, not Puppeteer's needs
4. **Minimal Implementation**: Comprehensive but minimal - implements all required nodes and edges

### Core Classes

#### Infrastructure Classes

- **EventEmitter** (`event_emitter.rb`): Event subscription and emission system
- **Disposable** (`disposable.rb`): Resource management with DisposableStack pattern
- **Errors** (`errors.rb`): Custom exception hierarchy for type-safe error handling

#### Protocol Management Classes

- **Session** (`session.rb`): BiDi session management, wraps Connection
- **Browser** (`browser.rb`): Browser instance management with user contexts
- **UserContext** (`user_context.rb`): Isolated browsing contexts (incognito-like)
- **BrowsingContext** (`browsing_context.rb`): Tab/window/iframe management with full BiDi operations
- **Navigation** (`navigation.rb`): Navigation lifecycle tracking with nested navigation support
- **Request** (`request.rb`): Network request management with interception
- **UserPrompt** (`user_prompt.rb`): User prompt (alert/confirm/prompt) handling

#### JavaScript Execution Classes

- **Realm** (`realm.rb`): Base class for JavaScript execution contexts
  - **WindowRealm**: Window and iframe script execution
  - **DedicatedWorkerRealm**: Web Worker script execution
  - **SharedWorkerRealm**: Shared Worker script execution

### Exception Hierarchy

```
StandardError
└── Puppeteer::Bidi::Error
    └── Puppeteer::Bidi::Core::Error
        └── Puppeteer::Bidi::Core::DisposedError
            ├── RealmDestroyedError
            ├── BrowsingContextClosedError
            ├── UserContextClosedError
            ├── UserPromptClosedError
            ├── SessionEndedError
            └── BrowserDisconnectedError
```

### Usage Example

```ruby
# Create session from existing connection
session = Puppeteer::Bidi::Core::Session.new(connection, session_info)

# Create browser and get default context
browser = Puppeteer::Bidi::Core::Browser.from(session)
session.browser = browser
context = browser.default_user_context

# Create browsing context (tab)
browsing_context = context.create_browsing_context('tab')

# Navigate and evaluate JavaScript
browsing_context.navigate('https://example.com', wait: 'complete')
result = browsing_context.default_realm.evaluate('document.title', true)
puts result['value']  # => "Example Domain"

# Handle errors
begin
  browsing_context.navigate('https://example.com')
rescue Puppeteer::Bidi::Core::BrowsingContextClosedError => e
  puts "Context was closed: #{e.reason}"
end
```

### Event Handling Pattern

Core classes use EventEmitter for async event handling:

```ruby
# Listen for navigation events
browsing_context.on(:navigation) do |data|
  navigation = data[:navigation]
  puts "Navigation started"
end

# Listen for load events
browsing_context.on(:load) do
  puts "Page loaded"
end

# Subscribe to BiDi events
browsing_context.subscribe([
  'browsingContext.navigationStarted',
  'browsingContext.load'
])
```

### Resource Management

Core classes implement Disposable pattern for proper cleanup:

```ruby
# Resources are automatically disposed when parent is disposed
browser.close  # Disposes all user contexts, browsing contexts, etc.

# Check disposal status
browsing_context.closed?  # => true
browsing_context.disposed?  # => true
```

For detailed documentation, see `lib/puppeteer/bidi/core/README.md`.

## Development Roadmap

### Phase 1: Foundation ✅ COMPLETED

- [x] WebSocket communication layer (`lib/puppeteer/bidi/transport.rb`)
- [x] Basic BiDi protocol implementation (`lib/puppeteer/bidi/connection.rb`)
- [x] Browser/BrowserContext/Page base classes (`lib/puppeteer/bidi/browser.rb`)
- [x] **Core layer implementation** (`lib/puppeteer/bidi/core/`)
  - EventEmitter and Disposable patterns
  - Session management
  - Browser, UserContext, BrowsingContext classes
  - Navigation, Request, UserPrompt classes
  - Realm classes (WindowRealm, DedicatedWorkerRealm, SharedWorkerRealm)
  - Custom exception hierarchy

### Phase 2: Core Features ✅ COMPLETED

- [x] Navigation (`browsingContext.navigate`)
- [x] **Page.waitForNavigation and Frame.waitForNavigation** - Navigation waiting with timeout support
  - Handles full page navigation, fragment navigation (#hash), and History API (pushState/replaceState)
  - Block-based API to hide Async complexity from users
  - Event-driven pattern with proper listener cleanup
  - Supports networkidle0 and networkidle2 wait conditions
- [x] **Page.waitForNetworkIdle** - Network idle detection
  - Tracks inflight network requests via BiDi network events
  - Configurable idle time (default: 500ms) and concurrency threshold (0 or 2)
  - Callback-based implementation using EventEmitter pattern
  - Integrated into wait_for_navigation for networkidle conditions
- [x] JavaScript execution (`script.evaluate`, `script.callFunction`)
- [x] **Page.evaluate and Frame.evaluate** - Full JavaScript evaluation with argument serialization
- [x] Event handling system (EventEmitter)
- [x] **Element operations** - Click, scroll, element visibility detection
  - Mouse input (`input.performActions`)
  - ElementHandle#click with automatic scrolling
  - Wrapped element support (getClientRects)
  - Viewport clipping algorithm
- [ ] FrameManager implementation - **TODO**

### Phase 3: Advanced Features 🚧 IN PROGRESS

- [x] Network request management (Request class)
- [x] **Network request tracking** (BrowsingContext inflight counter)
  - Tracks inflight requests via network.beforeRequestSent/responseCompleted/fetchError
  - Emits :inflight_changed events for network idle detection
  - Thread-safe counter with mutex protection
- [ ] NetworkManager implementation - **TODO**
- [ ] Network interception (partial support in Request)
- [x] Screenshot/PDF generation (BrowsingContext methods)
- [x] Enhanced event handling (Core layer)

### Phase 4: Stabilization 🚧 IN PROGRESS

- [x] Error handling (Custom exception classes)
- [ ] Timeout management - **TODO**
- [x] Test suite development (integration tests)
- [x] Documentation enhancement (Core README.md)

## Technical Considerations

### Performance

- Single operations may involve multiple communication round-trips
- WebSocket connection maintenance cost
- Event listener memory management

### Reliability

- Reconnection strategy for WebSocket disconnections
- Appropriate timeout settings
- Cleanup on error conditions

### Debugging

- BiDi protocol message logging
- Internal state visualization
- WebSocket traffic monitoring

## References

### Specifications & Documentation

- [WebDriver BiDi Specification](https://w3c.github.io/webdriver-bidi/)
- [Puppeteer Documentation](https://pptr.dev/)
- [Puppeteer Source Code](https://github.com/puppeteer/puppeteer)

### Implementation References

- [puppeteer-ruby](https://github.com/YusukeIwaki/puppeteer-ruby) - CDP implementation reference
- [Puppeteer BiDi implementation](https://github.com/puppeteer/puppeteer/tree/main/packages/puppeteer-core/src/bidi) - Original implementation

## Coding Conventions

### Ruby Conventions

- Use Ruby 3.0+ features
- Follow RuboCop guidelines
- Provide RBS type definitions

### Naming Conventions

- Class names: `PascalCase`
- Method names: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`

### Testing

- Use RSpec
- Unit tests + integration tests
- Appropriate use of mocks/stubs

### Test Organization

- **Unit tests**: `spec/` - Fast, isolated component tests
- **Integration tests**: `spec/integration/` - End-to-end browser automation tests
- Run integration tests: `bundle exec rspec spec/integration/`
- Integration tests launch actual Firefox browser instances

### Integration Test Helpers

The `spec/spec_helper.rb` provides a `with_browser` helper for integration tests:

```ruby
# spec/integration/my_test_spec.rb
RSpec.describe 'my feature' do
  example 'test something' do
    with_browser do |browser|
      # Browser is automatically launched and closed
      result = browser.new_context(type: 'tab')
      # ... test code
    end
  end
end
```

**Environment Variables:**

- `HEADLESS=false` - Run browser in non-headless mode (default: headless)

## Async Programming with socketry/async

This project uses the [socketry/async](https://github.com/socketry/async) library for asynchronous operations.

### Why Async Instead of concurrent-ruby?

**IMPORTANT**: This project uses `Async` (Fiber-based), **NOT** `concurrent-ruby` (Thread-based).

| Feature               | Async (Fiber-based)                                    | concurrent-ruby (Thread-based)         |
| --------------------- | ------------------------------------------------------ | -------------------------------------- |
| **Concurrency Model** | Cooperative multitasking (like JavaScript async/await) | Preemptive multitasking                |
| **Race Conditions**   | ✅ Not possible within a Fiber                         | ❌ Requires Mutex, locks, etc.         |
| **Synchronization**   | ✅ Not needed (cooperative)                            | ❌ Required (Mutex, Semaphore)         |
| **Mental Model**      | ✅ Similar to JavaScript async/await                   | ❌ Traditional thread programming      |
| **Bug Risk**          | ✅ Lower (no race conditions)                          | ❌ Higher (race conditions, deadlocks) |

**Key advantages:**

- **No race conditions**: Fibers yield control cooperatively, so no concurrent access to shared state
- **No Mutex needed**: Since there are no race conditions, no synchronization primitives required
- **Similar to JavaScript**: If you understand `async/await` in JavaScript, you understand Async in Ruby
- **Easier to reason about**: Code executes sequentially within a Fiber until it explicitly yields

**Example:**

```ruby
# ❌ DON'T: Use concurrent-ruby (Thread-based, requires Mutex)
require 'concurrent'
@pending = Concurrent::Map.new  # Thread-safe map
promise = Concurrent::Promises.resolvable_future
promise.fulfill(value)

# ✅ DO: Use Async (Fiber-based, no synchronization needed)
require 'async/promise'
@pending = {}  # Plain Hash is safe with Fibers
promise = Async::Promise.new
promise.resolve(value)
```

### Best Practices

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

### AsyncUtils: Promise.all and Promise.race

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

- ✅ **Parallel task execution**: Running multiple independent async operations
- ✅ **Racing timeouts**: First of multiple operations to complete
- ❌ **Event-driven waiting**: Use `Async::Promise` directly for event listeners

**Example - NOT suitable for event-driven patterns:**

```ruby
# ❌ DON'T: Use promise_race for event listeners
# The current wait_for_navigation implementation is event-driven and uses
# Async::Promise directly, which is more appropriate than promise_race.
# promise_race is for racing independent tasks, not coordinating event listeners.
```

See `spec/async_utils_spec.rb` for comprehensive usage examples.

### Current Implementation

The Browser class uses this pattern for WebSocket connection management:

```ruby
# lib/puppeteer/bidi/browser.rb
connection_task = Thread.new do
  Sync do
    transport.connect
  end
end
```

This ensures:

- Async operations run efficiently in an event loop
- Main thread remains responsive
- Proper cleanup on browser close

### WebSocket Message Handling Pattern

**CRITICAL**: BiDi message handling must use `Async do` to process messages asynchronously:

```ruby
# lib/puppeteer/bidi/transport.rb
while (message = connection.read)
  next if message.nil?

  # ✅ DO: Use Async do for non-blocking message processing
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

- ❌ **Without `Async do`**: Message processing blocks the message loop, preventing other messages from being read
- ✅ **With `Async do`**: Each message is processed in a separate fiber, allowing concurrent message handling
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

### Navigation Implementation Example

The `Frame#wait_for_navigation` demonstrates proper Async/Fiber-based patterns:

```ruby
# lib/puppeteer/bidi/frame.rb
def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
  # Use Async::Promise for event coordination (NOT Thread-based)
  promise = Async::Promise.new

  # Set up event listeners
  @browsing_context.on(:navigation) do |data|
    navigation = data[:navigation]

    # Resolve promise when navigation completes
    navigation.once(:load) do
      promise.resolve(:full_page)
    end
  end

  # Check for existing navigation (Puppeteer pattern)
  existing_nav = @browsing_context.navigation
  if existing_nav && !existing_nav.disposed?
    # Attach to existing navigation
    setup_navigation_listeners.call(existing_nav)
  end

  # Execute block (may trigger navigation)
  block.call if block

  # Wait using Async (Fiber-based, not Thread-based)
  result = Async do |task|
    task.with_timeout(timeout / 1000.0) do
      promise.wait
    end
  end.wait

  result == :full_page ? HTTPResponse.new(...) : nil
ensure
  # Always clean up listeners
  @browsing_context.off(:navigation, &navigation_listener)
end
```

**Key points:**

- ✅ Uses `Async::Promise` for signaling (Fiber-based)
- ✅ No `Sync` wrapper at method level (avoids nesting issues)
- ✅ Checks for existing navigation before executing block
- ✅ Proper cleanup in `ensure` block
- ✅ Matches Puppeteer's Promise-based pattern

**Usage:**

```ruby
# Block pattern (existing tests compatible)
page.wait_for_navigation do
  page.click('a')
end

# Can be called from Async context
Async do
  page.wait_for_navigation(wait_until: 'domcontentloaded')
end
```

### References

- [Async Best Practices](https://socketry.github.io/async/guides/best-practices/)
- [Async Documentation](https://socketry.github.io/async/)
- [Async::Barrier Guide](https://socketry.github.io/async/guides/tasks/index.html)

## Two-Layer Async Architecture

This codebase implements a two-layer architecture to separate async complexity from user-facing APIs.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Upper Layer (Puppeteer::Bidi)                          │
│  - User-facing, synchronous API                         │
│  - Calls .wait internally on Core layer methods         │
│  - Examples: Page, Frame, JSHandle, ElementHandle       │
├─────────────────────────────────────────────────────────┤
│  Core Layer (Puppeteer::Bidi::Core)                     │
│  - Returns Async::Task for all async operations         │
│  - Uses async_send_command internally                   │
│  - Examples: Session, BrowsingContext, Realm            │
└─────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Core Layer (Puppeteer::Bidi::Core)**:
   - All methods that communicate with BiDi protocol return `Async::Task`
   - Uses `session.async_send_command` (not `send_command`)
   - Methods are explicitly async and composable
   - Examples: `BrowsingContext#navigate`, `Realm#call_function`

2. **Upper Layer (Puppeteer::Bidi)**:
   - All methods call `.wait` on Core layer async operations
   - Provides synchronous, blocking API for users
   - Users never see `Async::Task` directly
   - Examples: `Page#goto`, `Frame#evaluate`, `JSHandle#get_property`

### Implementation Patterns

#### Core Layer Pattern

```ruby
# lib/puppeteer/bidi/core/browsing_context.rb
def navigate(url, wait: nil)
  Async do
    raise BrowsingContextClosedError, @reason if closed?
    params = { context: @id, url: url }
    params[:wait] = wait if wait
    result = session.async_send_command('browsingContext.navigate', params).wait
    result
  end
end

def perform_actions(actions)
  raise BrowsingContextClosedError, @reason if closed?
  session.async_send_command('input.performActions', {
    context: @id,
    actions: actions
  })
end
```

**Key points:**
- Returns `Async::Task` (implicitly from `Async do` block or explicitly from `async_send_command`)
- Users of Core layer must call `.wait` to get results

#### Upper Layer Pattern

```ruby
# lib/puppeteer/bidi/frame.rb
def goto(url, wait_until: 'load', timeout: 30000)
  response = wait_for_navigation(timeout: timeout, wait_until: wait_until) do
    @browsing_context.navigate(url, wait: 'interactive').wait  # ← .wait call
  end
  HTTPResponse.new(url: @browsing_context.url, status: 200)
end

# lib/puppeteer/bidi/keyboard.rb
def perform_actions(action_list)
  @browsing_context.perform_actions([
    {
      type: 'key',
      id: 'default keyboard',
      actions: action_list
    }
  ]).wait  # ← .wait call
end

# lib/puppeteer/bidi/js_handle.rb
def get_property(property_name)
  assert_not_disposed

  result = @realm.call_function(
    '(object, property) => object[property]',
    false,
    arguments: [
      @remote_value,
      Serializer.serialize(property_name)
    ]
  ).wait  # ← .wait call

  if result['type'] == 'exception'
    exception_details = result['exceptionDetails']
    text = exception_details['text'] || 'Evaluation failed'
    raise text
  end

  JSHandle.from(result['result'], @realm)
end
```

**Key points:**
- Always calls `.wait` on Core layer methods
- Returns plain Ruby objects (String, Hash, etc.), not Async::Task
- User-facing API is synchronous

### Common Mistakes and How to Fix Them

#### Mistake 1: Forgetting .wait on Core Layer Methods

```ruby
# ❌ WRONG: Missing .wait
def query_selector(selector)
  result = @realm.call_function(
    '(element, selector) => element.querySelector(selector)',
    false,
    arguments: [@remote_value, Serializer.serialize(selector)]
  )

  if result['type'] == 'exception'  # ← Error: undefined method '[]' for Async::Task
    # ...
  end
end

# ✅ CORRECT: Add .wait
def query_selector(selector)
  result = @realm.call_function(
    '(element, selector) => element.querySelector(selector)',
    false,
    arguments: [@remote_value, Serializer.serialize(selector)]
  ).wait  # ← Add .wait here

  if result['type'] == 'exception'
    # ...
  end
end
```

#### Mistake 2: Using send_command Instead of async_send_command in Core Layer

```ruby
# ❌ WRONG: Using send_command (doesn't exist)
def perform_actions(actions)
  session.send_command('input.performActions', {  # ← Error: undefined method
    context: @id,
    actions: actions
  })
end

# ✅ CORRECT: Use async_send_command
def perform_actions(actions)
  session.async_send_command('input.performActions', {
    context: @id,
    actions: actions
  })
end
```

#### Mistake 3: Not Calling .wait on All Core Methods

```ruby
# ❌ WRONG: Multiple Core calls, only one .wait
def get_properties
  result = @realm.call_function(...).wait  # ← OK

  properties_object = result['result']

  props_result = @realm.call_function(...)  # ← Missing .wait!

  if props_result['type'] == 'exception'  # ← Error
    # ...
  end
end

# ✅ CORRECT: Add .wait to all Core calls
def get_properties
  result = @realm.call_function(...).wait

  properties_object = result['result']

  props_result = @realm.call_function(...).wait  # ← Add .wait

  if props_result['type'] == 'exception'
    # ...
  end
end
```

### Checklist for Adding New Methods

When adding new methods to the Upper Layer:

1. ✅ Identify all calls to Core layer methods
2. ✅ Add `.wait` to each Core layer method call
3. ✅ Verify the method returns plain Ruby objects, not Async::Task
4. ✅ Test with integration specs (keyboard_spec, jshandle_spec, etc.)

When adding new methods to the Core Layer:

1. ✅ Use `session.async_send_command` (not `send_command`)
2. ✅ Wrap in `Async do ... end` if needed
3. ✅ Return `Async::Task` (don't call .wait)
4. ✅ Document that callers must call .wait

### Files Modified for Async Architecture

The following files were updated to implement the two-layer async architecture:

**Core Layer:**
- `lib/puppeteer/bidi/core/session.rb` - Changed `send_command` → `async_send_command`
- `lib/puppeteer/bidi/core/browsing_context.rb` - All methods use `async_send_command`
- `lib/puppeteer/bidi/core/realm.rb` - Methods return `Async::Task`

**Upper Layer:**
- `lib/puppeteer/bidi/realm.rb` - Added `.wait` to `execute_with_core`, `call_function`
- `lib/puppeteer/bidi/frame.rb` - Added `.wait` to `goto`
- `lib/puppeteer/bidi/js_handle.rb` - Added `.wait` to `dispose`, `get_property`, `get_properties`, `as_element`
- `lib/puppeteer/bidi/element_handle.rb` - Added `.wait` to `query_selector_all`, `eval_on_selector_all`
- `lib/puppeteer/bidi/keyboard.rb` - Added `.wait` to `perform_actions`
- `lib/puppeteer/bidi/mouse.rb` - Added `.wait` to `perform_actions`
- `lib/puppeteer/bidi/page.rb` - Added `.wait` to `capture_screenshot`, `close`, `set_viewport`, `set_javascript_enabled`

## Implementation Best Practices

### Porting Puppeteer Tests to Ruby

#### 1. Reference Implementation First

**Always consult the official Puppeteer implementation before implementing features:**

- **TypeScript source files**:

  - `packages/puppeteer-core/src/bidi/Page.ts` - High-level Page API
  - `packages/puppeteer-core/src/bidi/BrowsingContext.ts` - Core BiDi context
  - `packages/puppeteer-core/src/api/Page.ts` - Common Page interface

- **Test files**:
  - `test/src/screenshot.spec.ts` - Screenshot test suite
  - `test/golden-firefox/` - Golden images for visual regression testing

**Example workflow:**

```ruby
# 1. Read Puppeteer's TypeScript implementation
# 2. Understand the BiDi protocol calls being made
# 3. Implement Ruby equivalent with same logic flow
# 4. Port corresponding test cases
```

#### 2. Test Infrastructure Setup

**Use async-http for test servers** (lightweight + Async-friendly):

```ruby
# spec/support/test_server.rb
endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{@port}")

server = Async::HTTP::Server.for(endpoint) do |request|
  if handler = lookup_route(request.path)
    notify_request(request.path)
    respond_with_handler(handler, request)
  else
    serve_static_asset(request)
  end
end

server.run
```

**Helper pattern for integration tests:**

```ruby
# spec/spec_helper.rb

# Optimized helper - reuses shared browser, creates new page per test
# This is much faster as it avoids browser launch overhead
def with_test_state
  # Create a new page (tab) for this test
  page = $shared_browser.new_page
  context = $shared_browser.default_browser_context

  begin
    yield(page: page, server: $shared_test_server, browser: $shared_browser, context: context)
  ensure
    # Close the page to clean up resources
    page.close unless page.closed?
  end
end

# Legacy helper - launches a new browser for each call
# Use with_test_state for better performance
def with_browser(**options)
  options[:headless] = headless_mode?
  browser = Puppeteer::Bidi.launch(**options)
  yield(browser)
ensure
  browser&.close
end
```

**Performance optimization:**

- `with_test_state` reuses a shared browser instance (`$shared_browser`) across all tests
- Each test gets a new page (tab) instead of launching a new browser
- Shared test server (`$shared_test_server`) eliminates server restart overhead
- Tests that need custom browser options should use `with_browser` directly

#### 3. Golden Image Testing

**Download and compare pixel-by-pixel with tolerance:**

```bash
# Download golden images
curl -sL https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/golden-firefox/screenshot-sanity.png \
  -o spec/golden-firefox/screenshot-sanity.png
```

**Implement tolerant comparison** (rendering engines differ slightly):

```ruby
def compare_with_golden(screenshot_base64, golden_filename,
                        max_diff_pixels: 0,
                        pixel_threshold: 1)
  # pixel_threshold: 1 allows ±1 RGB difference per channel
  # Handles Firefox version/platform rendering variations
end
```

#### 4. BiDi Protocol Data Deserialization

**BiDi returns values in special format - always deserialize:**

```ruby
# BiDi response format:
# [["width", {"type" => "number", "value" => 500}],
#  ["height", {"type" => "number", "value" => 1000}]]

def deserialize_result(result)
  value = result['value']
  return value unless value.is_a?(Array)

  # Convert to Ruby Hash
  if value.all? { |item| item.is_a?(Array) && item.length == 2 }
    value.each_with_object({}) do |(key, val), hash|
      hash[key] = deserialize_value(val)
    end
  else
    value
  end
end

def deserialize_value(val)
  case val['type']
  when 'number' then val['value']
  when 'string' then val['value']
  when 'boolean' then val['value']
  when 'undefined', 'null' then nil
  else val['value']
  end
end
```

#### 5. Implementing Puppeteer-Compatible APIs

**Follow Puppeteer's exact logic flow:**

Example: `fullPage` screenshot implementation

```ruby
# From Puppeteer's Page.ts:
# if (options.fullPage) {
#   if (!options.captureBeyondViewport) {
#     // Resize viewport to full page
#   }
# } else {
#   options.captureBeyondViewport = false;
# }

if full_page
  unless capture_beyond_viewport
    scroll_dimensions = evaluate(...)
    set_viewport(scroll_dimensions)
    begin
      data = capture_screenshot(origin: 'viewport')
    ensure
      set_viewport(original_viewport)  # Always restore
    end
  else
    options[:origin] = 'document'
  end
elsif !clip
  capture_beyond_viewport = false  # Match Puppeteer behavior
end
```

**Key principles:**

- Use `begin/ensure` blocks for cleanup (viewport restoration, etc.)
- Match Puppeteer's parameter defaults exactly
- Follow the same conditional logic order

#### 6. Layer Architecture

**Maintain clear separation:**

```
High-level API (lib/puppeteer/bidi/)
├── Browser        - User-facing browser interface
├── BrowserContext - Session management
└── Page           - Page automation API

Core Layer (lib/puppeteer/bidi/core/)
├── Session        - BiDi session management
├── Browser        - Low-level browser operations
├── UserContext    - BiDi user context
└── BrowsingContext - BiDi browsing context (tab/frame)
```

**Implementation pattern:**

```ruby
# High-level Page wraps Core::BrowsingContext
class Page
  def initialize(browser_context, browsing_context)
    @browsing_context = browsing_context  # Core layer
  end

  def screenshot(...)
    # High-level logic
    data = @browsing_context.capture_screenshot(...)  # Delegate to core
    # Post-processing
  end
end
```

#### 7. Multiple Pages and Parallel Execution

**Creating multiple pages in same context:**

```ruby
# Browser exposes default_browser_context
class Browser
  attr_reader :default_browser_context

  def new_page
    @default_browser_context.new_page
  end
end

# Test can access context to create multiple pages
with_test_state do |page:, context:, **|
  pages = (0...2).map do
    new_page = context.new_page
    new_page.goto("#{server.prefix}/grid.html")
    new_page
  end

  # Run in parallel using Ruby threads
  threads = pages.map do |p|
    Thread.new { p.screenshot(...) }
  end
  screenshots = threads.map(&:value)

  pages.each(&:close)
end
```

**Key points:**

- BrowserContext manages multiple Page instances
- Pages in same context share cookies/localStorage but have separate browsing contexts
- Thread-safe screenshot execution (BiDi protocol handles concurrency)

#### 8. Setting Page Content

**Use data URLs with base64 encoding:**

```ruby
def set_content(html, wait_until: 'load')
  # Encode HTML in base64 to avoid URL encoding issues
  encoded = Base64.strict_encode64(html)
  data_url = "data:text/html;base64,#{encoded}"
  goto(data_url, wait_until: wait_until)
end
```

**Why base64:**

- Avoids URL encoding issues with special characters
- Handles multi-byte characters correctly
- Standard approach in browser automation tools

#### 9. Viewport Restoration

**Always restore viewport after temporary changes:**

```ruby
# Save current viewport (may be nil)
original_viewport = viewport

# If no viewport set, save window size
unless original_viewport
  original_size = evaluate('({ width: window.innerWidth, height: window.innerHeight })')
  original_viewport = { width: original_size['width'].to_i, height: original_size['height'].to_i }
end

# Change viewport temporarily
set_viewport(width: new_width, height: new_height)

begin
  # Do work
ensure
  # Always restore
  set_viewport(**original_viewport) if original_viewport
end
```

**Important:**

- Use `begin/ensure` to guarantee restoration even on errors
- Handle nil viewport case (no explicit viewport was set)
- Save window.innerWidth/innerHeight as fallback

## Implementation Details

The following topics have detailed documentation in the `CLAUDE/` directory:

### JavaScript and DOM Interaction

- **[JavaScript Evaluation](CLAUDE/javascript_evaluation.md)** - `evaluate()` and `evaluate_handle()` implementation

  - IIFE detection logic
  - Argument serialization to BiDi LocalValue format
  - Result deserialization
  - Core::Realm return values

- **[JSHandle and ElementHandle](CLAUDE/jshandle_implementation.md)** - Object and element handle management

  - BiDi protocol parameters (resultOwnership, serializationOptions)
  - Handle lifecycle and disposal
  - Debugging with DEBUG_BIDI_COMMAND=1
  - Common pitfalls and solutions

- **[Selector Evaluation Methods](CLAUDE/selector_evaluation.md)** - `eval_on_selector` and `eval_on_selector_all`
  - Method naming convention (Ruby cannot use `$`)
  - Delegation pattern: Page → Frame → ElementHandle
  - Handle lifecycle management
  - Performance considerations

### Error Handling

- **[Error Handling and Custom Exceptions](CLAUDE/error_handling.md)** - Type-safe error handling
  - Custom exception hierarchy
  - When to use each exception type
  - Implementation patterns
  - Benefits of type safety

### User Input and Interactions

- **[Click Implementation](CLAUDE/click_implementation.md)** - Mouse input and click functionality

  - Architecture: Page → Frame → ElementHandle delegation
  - Mouse class and BiDi input.performActions
  - Critical bug fixes (session.subscribe, event-based URL updates)
  - BiDi protocol format requirements

- **[Wrapped Element Click](CLAUDE/wrapped_element_click.md)** - getClientRects() for multi-line elements
  - Why getBoundingClientRect() fails for wrapped text
  - intersectBoundingBoxesWithFrame viewport clipping
  - Debugging techniques

### Navigation

- **[Navigation Waiting Pattern](CLAUDE/navigation_waiting.md)** - `Page.waitForNavigation` and `Frame.waitForNavigation`
  - Three navigation types: full page, fragment (#hash), History API
  - Event-driven waiting pattern with Async::Promise
  - Why AsyncUtils.promise_race doesn't simplify this pattern
  - Navigation object integration and race condition prevention
  - Comprehensive test coverage

### Testing

- **[Testing Strategy](CLAUDE/testing_strategy.md)** - Integration tests and optimization

  - Test organization and structure
  - Performance optimization (19x faster with browser reuse)
  - Golden image testing
  - Environment variables

- **[RSpec: pending vs skip](CLAUDE/rspec_pending_vs_skip.md)** - Documenting browser limitations

  - When to use `pending` (Firefox BiDi limitations)
  - When to use `skip` (unimplemented features)
  - Proper error trace documentation

- **[Test Server Dynamic Routes](CLAUDE/test_server_routes.md)** - Dynamic route handling for tests
  - `server.set_route(path)` for intercepting requests
  - `server.wait_for_request(path)` for synchronization
  - Testing navigation events (domcontentloaded vs load)
  - Known limitations and challenges

### Architecture

- **[Frame Architecture](CLAUDE/frame_architecture.md)** - Parent-based frame hierarchy
  - Constructor signature: `(parent, browsing_context)`
  - Recursive page traversal
  - Support for nested iframes

### Navigation Implementation

- **Navigation Tracking Pattern** - Following Puppeteer's BiDi Core implementation

  - `BrowsingContext#navigation` accessor exposes current navigation
  - `Frame#wait_for_navigation` can attach to existing navigations
  - Multiple `wait_for_navigation` calls can wait for same navigation
  - Supports different `wait_until` values ('load', 'domcontentloaded')

- **Async/Fiber-based Concurrency** - Following CLAUDE.md guidance

  - Uses `Async::Promise` for signaling (not Thread-based)
  - Cooperative multitasking (no race conditions)
  - No Mutex/locks required
  - Similar mental model to JavaScript's async/await

- **Implementation Pattern**:

  ```ruby
  # Check for existing navigation BEFORE executing block
  existing_nav = @browsing_context.navigation
  if existing_nav && !existing_nav.disposed?
    # Attach to the existing navigation
    setup_navigation_listeners.call(existing_nav)
  end

  # Execute block (may trigger new navigation)
  block.call if block

  # Wait using Async::Promise (Fiber-based)
  result = Async do |task|
    task.with_timeout(timeout_seconds) do
      promise.wait
    end
  end.wait
  ```

- **Navigation Event Types**:

  1. **Full page navigation**: `navigationStarted` → `load`/`domContentLoaded` → Returns HTTPResponse
  2. **Fragment navigation**: `fragmentNavigated` only → Returns nil
  3. **History API**: `historyUpdated` only → Returns nil

- **Key Differences from Thread-based**:
  - ❌ Thread-based: Race conditions, requires Mutex, unpredictable execution order
  - ✅ Fiber-based: Cooperative multitasking, no race conditions, predictable behavior
  - ✅ Matches Puppeteer's Promise-based pattern

## Summary

puppeteer-bidi aims to provide a Ruby implementation that inherits Puppeteer's design philosophy while leveraging WebDriver BiDi protocol characteristics. Through layered architecture, event-driven design, and adoption of standardized protocols, we deliver a reliable Firefox automation tool.

**Development workflow:**

1. Study Puppeteer's implementation first
2. Understand BiDi protocol calls
3. Implement with proper deserialization
4. Port tests with golden image verification
5. Handle platform/version rendering differences gracefully

**For detailed implementation guides, see the [CLAUDE/](CLAUDE/) directory.**

## Test Assets Policy

**CRITICAL**: Always use Puppeteer's official test assets without modification.

- **Source**: https://github.com/puppeteer/puppeteer/tree/main/test/assets
- **Rule**: Never modify test asset files (HTML, CSS, images) in `spec/assets/`
- **Experiments**: If you need to modify assets for experiments, **always revert to official version** before creating Pull Requests
- **Verification**: Before creating PR, verify all `spec/assets/` files match Puppeteer's official versions

**Example workflow**:

```bash
# During development - OK to experiment
vim spec/assets/test.html  # Temporary modification for debugging

# Before PR - MUST revert to official
curl -sL https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/assets/test.html \
  -o spec/assets/test.html
```

**Why this matters**: Test assets are designed to test specific edge cases (rotated elements, complex layouts, etc.). Using simplified versions defeats the purpose of these tests.

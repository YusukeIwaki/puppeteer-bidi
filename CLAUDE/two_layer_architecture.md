# Two-Layer Async Architecture

This codebase implements a two-layer architecture to separate async complexity from user-facing APIs.

## Architecture Overview

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

## Design Principles

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

## Implementation Patterns

### Core Layer Pattern

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

### Upper Layer Pattern

```ruby
# lib/puppeteer/bidi/frame.rb
def goto(url, wait_until: 'load', timeout: 30000)
  response = wait_for_navigation(timeout: timeout, wait_until: wait_until) do
    @browsing_context.navigate(url, wait: 'interactive').wait  # .wait call
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
  ]).wait  # .wait call
end
```

**Key points:**
- Always calls `.wait` on Core layer methods
- Returns plain Ruby objects (String, Hash, etc.), not Async::Task
- User-facing API is synchronous

## Common Mistakes and How to Fix Them

### Mistake 1: Forgetting .wait on Core Layer Methods

```ruby
# WRONG: Missing .wait
def query_selector(selector)
  result = @realm.call_function(...)
  if result['type'] == 'exception'  # Error: undefined method '[]' for Async::Task
    # ...
  end
end

# CORRECT: Add .wait
def query_selector(selector)
  result = @realm.call_function(...).wait  # Add .wait here
  if result['type'] == 'exception'
    # ...
  end
end
```

### Mistake 2: Using send_command Instead of async_send_command in Core Layer

```ruby
# WRONG: Using send_command (doesn't exist)
def perform_actions(actions)
  session.send_command('input.performActions', {...})  # Error: undefined method
end

# CORRECT: Use async_send_command
def perform_actions(actions)
  session.async_send_command('input.performActions', {...})
end
```

### Mistake 3: Not Calling .wait on All Core Methods

```ruby
# WRONG: Multiple Core calls, only one .wait
def get_properties
  result = @realm.call_function(...).wait  # OK
  props_result = @realm.call_function(...)  # Missing .wait!
  if props_result['type'] == 'exception'  # Error
    # ...
  end
end

# CORRECT: Add .wait to all Core calls
def get_properties
  result = @realm.call_function(...).wait
  props_result = @realm.call_function(...).wait  # Add .wait
  if props_result['type'] == 'exception'
    # ...
  end
end
```

## Checklist for Adding New Methods

When adding new methods to the Upper Layer:

1. Identify all calls to Core layer methods
2. Add `.wait` to each Core layer method call
3. Verify the method returns plain Ruby objects, not Async::Task
4. Test with integration specs

When adding new methods to the Core Layer:

1. Use `session.async_send_command` (not `send_command`)
2. Wrap in `Async do ... end` if needed
3. Return `Async::Task` (don't call .wait)
4. Document that callers must call .wait

## Files Modified for Async Architecture

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

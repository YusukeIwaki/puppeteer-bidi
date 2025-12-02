# Core Layer Gotchas

## Overview

This document covers non-obvious issues and pitfalls in the Core layer implementation.

## BrowsingContext: disposed? vs closed? Conflict

### The Problem

`BrowsingContext` uses both `Disposable::DisposableMixin` and defines `alias disposed? closed?`:

```ruby
class BrowsingContext < EventEmitter
  include Disposable::DisposableMixin

  def closed?
    !@reason.nil?
  end

  alias disposed? closed?
end
```

This creates a conflict:
- `DisposableMixin#dispose` checks `disposed?` before proceeding
- `disposed?` is aliased to `closed?`
- `closed?` returns `true` when `@reason` is set

### The Bug

Original `dispose_context` implementation:

```ruby
def dispose_context(reason)
  @reason = reason  # Sets @reason, making closed? return true
  dispose           # dispose checks disposed?/closed?, sees true, returns early!
end
```

**Result**: `:closed` event was never emitted because `dispose` returned early.

### The Fix

Set `@reason` AFTER calling `dispose`:

```ruby
def dispose_context(reason)
  # IMPORTANT: Call dispose BEFORE setting @reason
  # Otherwise disposed?/closed? returns true and dispose returns early
  dispose
  @reason = reason
end
```

### Additional Fix: Emit :closed Before @disposed = true

`EventEmitter#emit` returns early if `@disposed` is true. But `DisposableMixin#dispose` sets `@disposed = true` before calling `perform_dispose`. This means any events emitted in `perform_dispose` would be ignored.

Solution: Override `dispose` to emit `:closed` before calling `super`:

```ruby
def dispose
  return if disposed?

  @reason ||= 'Browsing context closed'
  emit(:closed, { reason: @reason })  # Emit BEFORE @disposed = true

  super  # This sets @disposed = true and calls perform_dispose
end
```

## EventEmitter and DisposableMixin @disposed Interaction

Both `EventEmitter` and `DisposableMixin` use `@disposed` instance variable:

```ruby
# EventEmitter
def emit(event, data = nil)
  return if @disposed  # Early return if disposed
  # ...
end

def dispose
  @disposed = true
  @listeners.clear
end

# DisposableMixin
def dispose
  return if @disposed
  @disposed = true
  perform_dispose
end
```

When a class includes both (like `BrowsingContext`), they share the same `@disposed` variable. This is usually fine, but be aware:

1. **Order matters**: If you need to emit events during disposal, do it BEFORE setting `@disposed = true`
2. **Check disposal state carefully**: Use `disposed?` method, not `@disposed` directly
3. **Override dispose if needed**: To emit events or do cleanup that requires the emitter to still be active

## Debugging Tips

### Enable BiDi Debug Logging

```bash
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/frame_spec.rb
```

### Track Disposal State

Add temporary debug logs:

```ruby
def dispose
  puts "[DEBUG] dispose called for #{@id}, disposed?=#{disposed?}"
  # ...
end
```

### Check Event Listener Registration

Verify listeners are registered on the correct instance:

```ruby
browsing_context.once(:closed) do
  puts "[DEBUG] :closed received for #{browsing_context.id}"
end
```

## Related Files

- `lib/puppeteer/bidi/core/browsing_context.rb` - BrowsingContext implementation
- `lib/puppeteer/bidi/core/event_emitter.rb` - EventEmitter base class
- `lib/puppeteer/bidi/core/disposable.rb` - DisposableMixin module

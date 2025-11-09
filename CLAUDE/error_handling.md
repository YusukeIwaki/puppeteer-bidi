# Error Handling and Custom Exceptions

This document covers the custom exception hierarchy, implementation patterns, and benefits of type-safe error handling in puppeteer-bidi.

### Philosophy

Use custom exception classes instead of inline string raises for:
- **Type safety**: Enable `rescue` by specific exception type
- **DRY principle**: Centralize error messages
- **Debugging**: Attach contextual data to exception objects
- **Consistency**: Uniform error handling across codebase

### Custom Exception Hierarchy

```ruby
StandardError
└── Puppeteer::Bidi::Error
    ├── JSHandleDisposedError
    ├── PageClosedError
    ├── FrameDetachedError
    └── SelectorNotFoundError
```

All custom exceptions inherit from `Puppeteer::Bidi::Error` for consistent rescue patterns.

### Exception Classes

#### JSHandleDisposedError

**When raised**: Attempting to use a disposed JSHandle or ElementHandle

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class JSHandleDisposedError < Error
  def initialize
    super('JSHandle is disposed')
  end
end
```

**Usage**:
```ruby
# JSHandle and ElementHandle
private

def assert_not_disposed
  raise JSHandleDisposedError if @disposed
end
```

**Affected methods**:
- `JSHandle#evaluate`, `#evaluate_handle`, `#get_property`, `#get_properties`, `#json_value`
- `ElementHandle#query_selector`, `#query_selector_all`, `#eval_on_selector`, `#eval_on_selector_all`

#### PageClosedError

**When raised**: Attempting to use a closed Page

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class PageClosedError < Error
  def initialize
    super('Page is closed')
  end
end
```

**Usage**:
```ruby
# Page
private

def assert_not_closed
  raise PageClosedError if closed?
end
```

**Affected methods**:
- `Page#goto`, `#set_content`, `#screenshot`

#### FrameDetachedError

**When raised**: Attempting to use a detached Frame

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class FrameDetachedError < Error
  def initialize
    super('Frame is detached')
  end
end
```

**Usage**:
```ruby
# Frame
private

def assert_not_detached
  raise FrameDetachedError if @browsing_context.closed?
end
```

**Affected methods**:
- `Frame#evaluate`, `#evaluate_handle`, `#document`

#### SelectorNotFoundError

**When raised**: CSS selector doesn't match any elements in `eval_on_selector`

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class SelectorNotFoundError < Error
  attr_reader :selector

  def initialize(selector)
    @selector = selector
    super("Error: failed to find element matching selector \"#{selector}\"")
  end
end
```

**Usage**:
```ruby
# ElementHandle#eval_on_selector
element_handle = query_selector(selector)
raise SelectorNotFoundError, selector unless element_handle
```

**Contextual data**: The `selector` value is accessible via the exception object for debugging.

### Implementation Pattern

#### 1. Define Custom Exception

```ruby
# lib/puppeteer/bidi/errors.rb
class MyCustomError < Error
  def initialize(context = nil)
    @context = context
    super("Error message with #{context}")
  end
end
```

#### 2. Add Private Assertion Method

```ruby
class MyClass
  private

  def assert_valid_state
    raise MyCustomError, @context if invalid?
  end
end
```

#### 3. Replace Inline Raises

```ruby
# Before
def my_method
  raise 'Invalid state' if invalid?
  # ...
end

# After
def my_method
  assert_valid_state
  # ...
end
```

### Benefits

**Type-safe error handling**:
```ruby
begin
  page.eval_on_selector('.missing', 'e => e.id')
rescue SelectorNotFoundError => e
  puts "Selector '#{e.selector}' not found"
rescue JSHandleDisposedError
  puts "Handle was disposed"
end
```

**Consistent error messages**: Single source of truth for error text

**Reduced duplication**: 16 inline raises eliminated across codebase

**Better debugging**: Exception objects carry contextual information

### Testing Custom Exceptions

Tests use regex matching for backward compatibility:

```ruby
# Test remains compatible with custom exception
expect {
  page.eval_on_selector('non-existing', 'e => e.id')
}.to raise_error(/failed to find element matching selector/)
```

This allows tests to pass with both string raises and custom exceptions.

### Refactoring Statistics

| Class | Inline Raises Replaced | Private Assert Method |
|-------|------------------------|----------------------|
| JSHandle | 5 | `assert_not_disposed` |
| ElementHandle | 4 + 1 (selector) | (inherited) |
| Page | 3 | `assert_not_closed` |
| Frame | 3 | `assert_not_detached` |
| **Total** | **16** | **3 methods** |

### Future Considerations

When adding new error conditions:

1. **Create custom exception** in `lib/puppeteer/bidi/errors.rb`
2. **Add to exception hierarchy** by inheriting from `Error`
3. **Include contextual data** as `attr_reader` if needed
4. **Create private assert method** in the relevant class
5. **Replace inline raises** with assert method calls
6. **Update tests** to use regex matching for flexibility

This pattern ensures consistency and maintainability across the entire codebase.


# JSHandle and ElementHandle Implementation

This document provides comprehensive details on implementing JSHandle and ElementHandle classes, including BiDi protocol parameters, debugging techniques, and common pitfalls.

### Overview

JSHandle and ElementHandle are fundamental classes for interacting with JavaScript objects in the browser. This section documents the implementation details and debugging techniques learned during development.

### Architecture

```
Puppeteer::Bidi
├── Serializer        # Ruby → BiDi LocalValue
├── Deserializer      # BiDi RemoteValue → Ruby
├── JSHandle          # JavaScript object reference
└── ElementHandle     # DOM element reference (extends JSHandle)
```

### Key Implementation Files

| File | Purpose | Lines |
|------|---------|-------|
| `lib/puppeteer/bidi/serializer.rb` | Centralized argument serialization | 136 |
| `lib/puppeteer/bidi/deserializer.rb` | Centralized result deserialization | 132 |
| `lib/puppeteer/bidi/js_handle.rb` | JavaScript object handles | 291 |
| `lib/puppeteer/bidi/element_handle.rb` | DOM element handles | 91 |

**Code reduction**: ~300 lines of duplicate serialization code eliminated from Frame and Page classes.

### Critical BiDi Protocol Parameters

#### 1. resultOwnership - Handle Lifecycle Management

**Problem**: BiDi returns `{"type" => "object"}` without `handle` or `sharedId`, making it impossible to reference the object later.

**Root Cause**: Missing `resultOwnership` parameter in `script.callFunction` and `script.evaluate`.

**Solution**: Always set `resultOwnership: 'root'` when you need a handle:

```ruby
# lib/puppeteer/bidi/core/realm.rb
def call_function(function_declaration, await_promise, **options)
  # Critical: Use 'root' ownership to keep handles alive
  unless options.key?(:resultOwnership)
    options[:resultOwnership] = 'root'
  end

  session.send_command('script.callFunction', {
    functionDeclaration: function_declaration,
    awaitPromise: await_promise,
    target: target,
    **options
  })
end
```

**BiDi resultOwnership values**:
- `'root'`: Keep handle alive (garbage collection resistant)
- `'none'`: Don't return handle (for one-time evaluations)

**Important**: Don't confuse with `awaitPromise`:
- `awaitPromise`: Controls whether to wait for promises to resolve
- `resultOwnership`: Controls handle lifecycle (independent concern)

#### 2. serializationOptions - Control Serialization Depth

**When requesting handles**, set `maxObjectDepth: 0` to prevent deep serialization:

```ruby
# When awaitPromise is false (returning handle):
options[:serializationOptions] = {
  maxObjectDepth: 0,  # Don't serialize, return handle
  maxDomDepth: 0      # Don't serialize DOM children
}
```

**Without serializationOptions**: BiDi may serialize the entire object graph, losing the handle reference.

### Debugging Techniques

#### 1. Protocol Message Inspection

Use `DEBUG_BIDI_COMMAND=1` to see all BiDi protocol messages:

```bash
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:24
```

**Output**:
```
[BiDi] Request script.callFunction: {
  id: 1,
  method: "script.callFunction",
  params: {
    functionDeclaration: "() => navigator",
    awaitPromise: false,
    target: {context: "..."},
    resultOwnership: "root",           # ← Check this!
    serializationOptions: {            # ← Check this!
      maxObjectDepth: 0
    }
  }
}

[BiDi] Response for script.callFunction: {
  type: "success",
  result: {
    type: "object",
    handle: "6af2844f-..."  # ← Should have handle!
  }
}
```

#### 2. Comparing with Puppeteer's Protocol Messages

**Workflow**:
1. Clone Puppeteer repository: `git clone https://github.com/puppeteer/puppeteer`
2. Set up Puppeteer: `npm install && npm run build`
3. Enable protocol logging: `DEBUG_PROTOCOL=1 npm test -- test/src/jshandle.spec.ts`
4. Compare messages side-by-side with Ruby implementation

**Example comparison**:
```bash
# Puppeteer (TypeScript)
DEBUG_PROTOCOL=1 npm test -- test/src/jshandle.spec.ts -g "should accept object handle"

# Ruby implementation
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:24
```

**Look for differences in**:
- Parameter names (camelCase vs snake_case)
- Missing parameters (resultOwnership, serializationOptions)
- Parameter values (arrays vs strings)

#### 3. Extracting Specific Protocol Messages

Use `grep` to filter specific BiDi methods:

```bash
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:227 \
  --format documentation 2>&1 | grep -A 5 "script\.disown"
```

**Output**:
```
[BiDi] Request script.disown: {
  id: 6,
  method: "script.disown",
  params: {
    target: {context: "..."},
    handles: "6af2844f-..."  # ← ERROR: Should be array!
  }
}
```

#### 4. Step-by-Step Protocol Flow Analysis

For complex issues, trace the entire flow:

```ruby
# Add temporary debugging in code
def evaluate_handle(script, *args)
  puts "1. Input script: #{script}"
  puts "2. Serialized args: #{serialized_args.inspect}"

  result = @realm.call_function(script, false, arguments: serialized_args)
  puts "3. BiDi result: #{result.inspect}"

  handle = JSHandle.from(result['result'], @realm)
  puts "4. Created handle: #{handle.inspect}"

  handle
end
```

### Common Pitfalls and Solutions

#### 1. Handle Parameters Must Be Arrays

**Problem**: BiDi error "Expected 'handles' to be an array, got [object String]"

**Root Cause**: `script.disown` expects `handles` parameter as array, but single string was passed:

```ruby
# WRONG
@realm.disown(handle_id)  # → {handles: "abc-123"}

# CORRECT
@realm.disown([handle_id])  # → {handles: ["abc-123"]}
```

**Location**: `lib/puppeteer/bidi/js_handle.rb:57`

**Fix**:
```ruby
def dispose
  handle_id = id
  @realm.disown([handle_id]) if handle_id  # Wrap in array
end
```

#### 2. Handle Not Returned from evaluate_handle

**Symptoms**:
- `remote_value['handle']` is `nil`
- BiDi returns `{"type" => "object"}` without handle
- Error: "Expected 'serializedKeyValueList' to be an array"

**Root Cause**: Missing `resultOwnership` and `serializationOptions` parameters

**Fix**: Add to `Core::Realm#call_function` (see section 1 above)

#### 3. Confusing awaitPromise with returnByValue

**Common mistake**: Thinking `awaitPromise` controls serialization

**Reality**:
- `awaitPromise`: Wait for promises? (`true`/`false`)
- `resultOwnership`: Return handle? (`'root'`/`'none'`)
- These are **independent** concerns!

**Example**:
```ruby
# Want handle to a promise result? Use both!
call_function(script, true, resultOwnership: 'root')  # await=true, handle=yes

# Want serialized promise result? Different!
call_function(script, true, resultOwnership: 'none')  # await=true, serialize=yes
```

#### 4. Date Serialization in json_value

**Problem**: Dates converted to strings instead of Time objects

**Wrong approach**:
```ruby
# DON'T: Using JSON.stringify loses BiDi's native date type
result = evaluate('(value) => JSON.stringify(value)')
JSON.parse(result)  # Date becomes string!
```

**Correct approach**:
```ruby
# DO: Use BiDi's built-in serialization
def json_value
  evaluate('(value) => value')  # BiDi handles dates natively
end
```

**BiDi date format**:
```ruby
# BiDi returns: {type: 'date', value: '2020-05-27T01:31:38.506Z'}
# Deserializer converts to: Time.parse('2020-05-27T01:31:38.506Z')
```

### Testing Strategy for Handle Implementation

#### Test Organization

```
spec/integration/
├── jshandle_spec.rb         # 21 tests - JSHandle functionality
├── queryselector_spec.rb    # 8 tests - DOM querying
└── evaluation_spec.rb       # Updated - ElementHandle arguments
```

#### Test Coverage Checklist

When implementing handle-related features, ensure tests cover:

- ✅ Handle creation from primitives and objects
- ✅ Handle passing as function arguments
- ✅ Property access (single and multiple)
- ✅ JSON value serialization
- ✅ Special values (dates, circular references, undefined)
- ✅ Type conversion (`as_element`)
- ✅ String representation (`to_s`)
- ✅ Handle disposal and error handling
- ✅ DOM querying (single and multiple)
- ✅ Empty result handling

#### Running Handle Tests

```bash
# All handle-related tests
bundle exec rspec spec/integration/jshandle_spec.rb spec/integration/queryselector_spec.rb

# With protocol debugging
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:24

# Specific test
bundle exec rspec spec/integration/jshandle_spec.rb:227 --format documentation
```

### Code Patterns and Best Practices

#### 1. Serializer Usage

**Always use Serializer** for argument preparation:

```ruby
# Good
args = [element, selector].map { |arg| Serializer.serialize(arg) }
call_function(script, true, arguments: args)

# Bad - manual serialization (duplicates logic)
args = [
  { type: 'object', handle: element.id },
  { type: 'string', value: selector }
]
```

#### 2. Deserializer Usage

**Always use Deserializer** for result processing:

```ruby
# Good
result = call_function(script, true)
Deserializer.deserialize(result['result'])

# Bad - manual deserialization (misses edge cases)
result['result']['value']  # Breaks for dates, handles, etc.
```

#### 3. Factory Pattern for Handle Creation

**Use `JSHandle.from`** for polymorphic handle creation:

```ruby
# Good - automatically creates ElementHandle for nodes
handle = JSHandle.from(remote_value, realm)

# Bad - manual type checking
if remote_value['type'] == 'node'
  ElementHandle.new(realm, remote_value)
else
  JSHandle.new(realm, remote_value)
end
```

#### 4. Handle Disposal Pattern

**Always check disposal state** before operations:

```ruby
def get_property(name)
  raise 'JSHandle is disposed' if @disposed

  # ... implementation
end
```

### Performance Considerations

#### Handle Lifecycle

**Handles consume browser memory** - dispose when no longer needed:

```ruby
# Manual disposal
handle = page.evaluate_handle('window')
# ... use handle
handle.dispose

# Automatic disposal via block (future enhancement)
page.evaluate_handle('window') do |handle|
  # handle automatically disposed after block
end
```

#### Serialization vs Handle References

**Trade-off**:
- **Serialization** (`resultOwnership: 'none'`): One-time use, no memory overhead
- **Handle** (`resultOwnership: 'root'`): Reusable, requires disposal

```ruby
# One-time evaluation - serialize
page.evaluate('document.title')  # No handle created

# Reusable reference - handle
handle = page.evaluate_handle('document')  # Keep for multiple operations
handle.evaluate('doc => doc.title')
handle.evaluate('doc => doc.body.innerHTML')
handle.dispose  # Clean up
```

### Reference Implementation Mapping

| Puppeteer TypeScript | Ruby Implementation | Notes |
|---------------------|---------------------|-------|
| `BidiJSHandle.from()` | `JSHandle.from()` | Factory method |
| `BidiJSHandle#dispose()` | `JSHandle#dispose` | Handle cleanup |
| `BidiJSHandle#jsonValue()` | `JSHandle#json_value` | Uses evaluate trick |
| `BidiJSHandle#getProperty()` | `JSHandle#get_property` | Single property |
| `BidiJSHandle#getProperties()` | `JSHandle#get_properties` | Walks prototype chain |
| `BidiElementHandle#$()` | `ElementHandle#query_selector` | CSS selector |
| `BidiElementHandle#$$()` | `ElementHandle#query_selector_all` | Multiple elements |
| `BidiSerializer.serialize()` | `Serializer.serialize()` | Centralized |
| `BidiDeserializer.deserialize()` | `Deserializer.deserialize()` | Centralized |

### Future Enhancements

Potential improvements for handle implementation:

1. **Automatic disposal**: Block-based API with automatic cleanup
2. **Handle pooling**: Reuse handle IDs to reduce memory overhead
3. **Lazy deserialization**: Defer conversion until value is accessed
4. **Type hints**: RBS type definitions for better IDE support
5. **Handle debugging**: Track handle creation/disposal for leak detection

### Lessons Learned

1. **Always compare protocol messages** with Puppeteer when debugging BiDi issues
2. **resultOwnership is critical** for handle-based APIs - always set it explicitly
3. **Don't confuse awaitPromise with serialization** - they control different aspects
4. **BiDi arrays must be arrays** - wrapping single values is often necessary
5. **Use Puppeteer's tricks** - like `evaluate('(value) => value')` for json_value
6. **Test disposal thoroughly** - handle lifecycle bugs are subtle and common
7. **Centralize serialization** - eliminates duplication and ensures consistency


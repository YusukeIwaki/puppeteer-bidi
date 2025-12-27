# ExposeFunction and EvaluateOnNewDocument Implementation

This document details the implementation of `Page.evaluateOnNewDocument` and `Page.exposeFunction`, which use BiDi preload scripts and `script.message` channel for communication.

## Page.evaluateOnNewDocument

Injects JavaScript to be evaluated before any page scripts run.

### BiDi Implementation

Uses `script.addPreloadScript` command:

```ruby
def evaluate_on_new_document(page_function, *args)
  expression = build_evaluation_expression(page_function, *args)
  script_id = @browsing_context.add_preload_script(expression).wait
  NewDocumentScriptEvaluation.new(script_id)
end
```

### Key Points

1. **Preload Scripts Persist**: Scripts added via `addPreloadScript` run on every navigation
2. **Argument Serialization**: Arguments are serialized into the script as JSON literals
3. **Return Value**: Returns a `NewDocumentScriptEvaluation` with the script ID for later removal

### Example

```ruby
# Inject code that runs before any page scripts
script = page.evaluate_on_new_document("window.injected = 123")
page.goto(server.empty_page)
result = page.evaluate("window.injected")  # => 123

# Remove when done
page.remove_script_to_evaluate_on_new_document(script.identifier)
```

## Page.exposeFunction

Exposes a Ruby callable as a JavaScript function on the page.

### BiDi Implementation

Uses `script.message` channel for bidirectional communication:

```
Page (JS)                    Ruby (ExposedFunction)
    |                              |
    |-- callback([resolve,reject,args]) -->|
    |                              |
    |<-- resolve(result) or reject(error) -|
```

### Key Components

#### 1. Channel Argument Pattern

BiDi uses a special `channel` argument type:

```ruby
def channel_argument
  {
    type: "channel",
    value: {
      channel: @channel,  # Unique channel ID
      ownership: "root"   # Keep handles alive
    }
  }
end
```

#### 2. Function Declaration

The exposed function creates a Promise that waits for the Ruby callback:

```javascript
(callback) => {
  Object.assign(globalThis, {
    [name]: function (...args) {
      return new Promise((resolve, reject) => {
        callback([resolve, reject, args]);
      });
    },
  });
}
```

#### 3. Message Handling

Ruby listens for `script.message` events and processes calls:

```ruby
def handle_message(params)
  return unless params["channel"] == @channel

  # Extract data handle with [resolve, reject, args]
  data_handle = JSHandle.from(params["data"], realm.core_realm)

  # Call Ruby function and send result back
  result = @apply.call(*args)
  send_result(data_handle, result)
end
```

### Session Event Subscription

**Important**: `script.message` must be subscribed in the session:

```ruby
# In Core::Session
def subscribe_to_events
  subscribe([
    "browsingContext.load",
    "browsingContext.domContentLoaded",
    # ... other events
    "script.message",  # Required for exposeFunction
  ]).wait
end
```

### Frame Handling

ExposedFunction handles dynamic frames by:

1. **Listening to frameattached**: Injects into new frames
2. **Using preload scripts**: For top-level browsing contexts (not iframes)
3. **Using callFunction**: For immediate injection into current context

```ruby
def inject_into_frame(frame)
  # Add preload script for top-level contexts only
  if frame.browsing_context.parent.nil?
    script_id = frame.browsing_context.add_preload_script(
      function_declaration,
      arguments: [channel]
    ).wait
  end

  # Always call function for immediate availability
  realm.core_realm.call_function(
    function_declaration,
    false,
    arguments: [channel]
  ).wait
end
```

### Error Handling

#### Standard Errors

Errors are serialized with name, message, and stack trace:

```ruby
def send_error(data_handle, error)
  name = error.class.name
  message = error.message
  stack = error.backtrace&.join("\n")

  data_handle.evaluate(<<~JS, name, message, stack)
    ([, reject], name, message, stack) => {
      const error = new Error(message);
      error.name = name;
      if (stack) { error.stack = stack; }
      reject(error);
    }
  JS
end
```

#### Non-Error Values (ThrownValue)

Ruby doesn't support `throw "string"` syntax. Use `ThrownValue`:

```ruby
class ThrownValue < StandardError
  attr_reader :value

  def initialize(value)
    @value = value
    super("Thrown value")
  end
end

# Usage
page.expose_function("throwValue") do |value|
  raise ExposedFunction::ThrownValue.new(value)
end
```

### Cleanup

Disposal removes the function from all frames and cleans up resources:

```ruby
def dispose
  session.off("script.message", &@listener)
  page.off(:frameattached, &@frame_listener)

  # Remove from globalThis
  remove_binding_from_frame(@frame)

  # Remove preload scripts
  @scripts.each do |frame, script_id|
    frame.browsing_context.remove_preload_script(script_id).wait
  end
end
```

## Testing Considerations

### CSP Headers

Some tests require Content-Security-Policy headers. Use `TestServer#set_csp`:

```ruby
server.set_csp("/empty.html", "script-src 'self'")
```

### Test Asset

`spec/assets/tamperable.html` captures `window.injected` before page scripts run:

```html
<script>
  window.result = window.injected;
</script>
```

## Common Pitfalls

### 1. Missing script.message Subscription

**Problem**: `exposeFunction` doesn't receive callbacks

**Solution**: Ensure `script.message` is in session event subscriptions

### 2. Ownership: "root" Required

**Problem**: JSHandle becomes invalid before processing

**Solution**: Use `ownership: "root"` in channel argument to keep handles alive

### 3. Preload Scripts for Iframes

**Problem**: `addPreloadScript` not supported for iframe contexts

**Solution**: Only use preload scripts for top-level contexts; use `callFunction` for iframes

### 4. TypeError on raise nil

**Problem**: Ruby's `raise nil` throws `TypeError: exception class/object expected`

**Solution**: Catch and convert to `send_thrown_value`:

```ruby
rescue TypeError => e
  if e.message.include?("exception class/object expected")
    send_thrown_value(data_handle, nil)
  else
    send_error(data_handle, e)
  end
end
```

## References

- [WebDriver BiDi script.message](https://w3c.github.io/webdriver-bidi/#event-script-message)
- [WebDriver BiDi addPreloadScript](https://w3c.github.io/webdriver-bidi/#command-script-addPreloadScript)
- [Puppeteer ExposedFunction.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/ExposedFunction.ts)

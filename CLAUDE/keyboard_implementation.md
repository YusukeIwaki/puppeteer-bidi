# Keyboard Implementation

This document describes the keyboard input implementation for WebDriver BiDi.

## Overview

The Keyboard class implements user keyboard input using the BiDi `input.performActions` protocol. It supports typing text, pressing individual keys, and handling modifier keys (Shift, Control, Alt, Meta).

## Architecture

### Class Structure

```
Keyboard
├── @page (Page) - Reference to the page for focused_frame access
├── @browsing_context (BrowsingContext) - Target context for input actions
└── @pressed_keys (Set) - Track currently pressed keys for modifier state
```

### Key Components

1. **Keyboard class** (`lib/puppeteer/bidi/keyboard.rb`)
   - High-level keyboard input API
   - Manages modifier key state
   - Converts Ruby key names to BiDi format

2. **Key mappings** (`lib/puppeteer/bidi/key_definitions.rb`)
   - Maps key names to Unicode code points
   - Handles special keys (Enter, Tab, Arrow keys, etc.)
   - Platform-specific keys (CtrlOrMeta)

## BiDi Protocol Usage

### input.performActions Format

```ruby
session.send_command('input.performActions', {
  context: browsing_context_id,
  actions: [
    {
      type: 'key',
      id: 'keyboard',
      actions: [
        { type: 'keyDown', value: 'a' },
        { type: 'keyUp', value: 'a' }
      ]
    }
  ]
})
```

### Key Value Format

BiDi accepts two formats for key values:

1. **Single character**: `'a'`, `'1'`, `'!'`
2. **Unicode escape**: `"\uE007"` for Enter, `"\uE008"` for Shift, etc.

## Implementation Details

### Modifier Keys

**Special handling for CtrlOrMeta**:
```ruby
KEY_DEFINITIONS = {
  'CtrlOrMeta' => {
    key: RUBY_PLATFORM.include?('darwin') ? 'Meta' : 'Control',
    code: RUBY_PLATFORM.include?('darwin') ? 'MetaLeft' : 'ControlLeft',
    location: 1
  }
}
```

**Modifier state tracking**:
```ruby
def down(key)
  definition = get_key_definition(key)
  @pressed_keys.add(definition[:key])
  # ... send keyDown action
end

def up(key)
  definition = get_key_definition(key)
  @pressed_keys.delete(definition[:key])
  # ... send keyUp action
end
```

### Type Method

The `type` method splits text into individual characters and presses each one:

```ruby
def type(text, delay: 0)
  text.each_char do |char|
    # Handle special keys (e.g., "\n" → Enter)
    if SPECIAL_CHAR_MAP[char]
      press(SPECIAL_CHAR_MAP[char])
    else
      press(char)
    end
    sleep(delay / 1000.0) if delay > 0
  end
end
```

### Send Character Method

The `send_character` method inserts text without triggering keydown/keyup events:

```ruby
def send_character(char)
  raise ArgumentError, 'Cannot send more than 1 character.' if char.length > 1

  # Get the focused frame (may be an iframe)
  focused_frame = @page.focused_frame

  # Execute insertText in the focused frame's realm
  focused_frame.isolated_realm.call_function(
    'function(char) { document.execCommand("insertText", false, char); }',
    false,
    arguments: [{ type: 'string', value: char }]
  )
end
```

## Focused Frame Detection

For iframe keyboard input, we need to detect which frame currently has focus.

### Implementation Pattern (from Puppeteer)

```ruby
# Page#focused_frame
def focused_frame
  handle = main_frame.evaluate_handle(<<~JS)
    () => {
      let win = window;
      while (
        win.document.activeElement instanceof win.HTMLIFrameElement ||
        win.document.activeElement instanceof win.HTMLFrameElement
      ) {
        if (win.document.activeElement.contentWindow === null) {
          break;
        }
        win = win.document.activeElement.contentWindow;
      }
      return win;
    }
  JS

  # Get context ID from window object
  remote_value = handle.remote_value
  context_id = remote_value['value']['context']

  # Find frame with matching context ID
  frames.find { |f| f.browsing_context.id == context_id }
end
```

### Why This Matters

When typing in an iframe:
1. The user focuses a textarea inside the iframe
2. `document.activeElement` in main frame points to the iframe element
3. We traverse `activeElement.contentWindow` to find the focused frame
4. `send_character` executes `insertText` in the correct frame's realm

## Firefox BiDi Behavior Differences

### Modifier + Character Input Events

**Puppeteer (Chrome CDP) behavior**:
- Shift + '!' → triggers input event
- Control + '!' → no input event
- Alt + '!' → no input event

**Firefox BiDi behavior**:
- Shift + '!' → triggers input event ✅
- Control + '!' → triggers input event ⚠️
- Alt + '!' → triggers input event ⚠️

**Test adaptation**:
```ruby
# Instead of strict equality:
expect(result).to eq("Keydown: ! Digit1 [#{modifier_key}]")

# Use include to handle extra input events:
expect(result).to include("Keydown: ! Digit1 [#{modifier_key}]")
```

### Modifier State Persistence

**Known limitation**: BiDi doesn't maintain modifier state across separate `performActions` calls.

**Workaround**: Combine all actions into a single `performActions` call when modifier state needs to persist.

## Testing

### Test Structure

```ruby
with_test_state do |page:, server:, **|
  page.goto("#{server.prefix}/input/keyboard.html")

  # Type text
  page.keyboard.type('Hello')

  # Verify result
  result = page.evaluate('() => globalThis.getResult()')
  expect(result).to eq('Keydown: H KeyH []')
end
```

### Test Assets

**Important**: `spec/assets/input/textarea.html` must define:
```html
<script>
  globalThis.result = '';
  globalThis.textarea = document.querySelector('textarea');
  textarea.addEventListener('input', () => result = textarea.value, false);
</script>
```

These global variables are used by multiple tests to verify keyboard input behavior.

## References

- **Puppeteer keyboard implementation**:
  - TypeScript: `packages/puppeteer-core/src/bidi/Input.ts`
  - Tests: `test/src/keyboard.spec.ts`
- **BiDi Specification**:
  - [input.performActions](https://w3c.github.io/webdriver-bidi/#command-input-performActions)
- **Key definitions**:
  - [W3C WebDriver Key Codes](https://www.w3.org/TR/webdriver/#keyboard-actions)

## Common Pitfalls

1. **Forgetting to update test assets**: Tests fail with "result is not defined" or "textarea is undefined"
   - Solution: Download official Puppeteer test assets

2. **Modifier state not persisting**: Separate `performActions` calls don't maintain modifier state
   - Solution: Combine actions in single call (current limitation)

3. **iframe input goes to main frame**: Text appears in wrong frame
   - Solution: Implement `focused_frame` detection

4. **Platform-specific Meta key**: Meta key doesn't work on Linux/Windows
   - Solution: Use CtrlOrMeta abstraction

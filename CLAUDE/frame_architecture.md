# Frame Architecture Implementation

## Overview

This document details the Frame architecture implementation following Puppeteer's parent-based design pattern.

## Architecture Change

### Before (Incorrect)

```ruby
class Frame
  def initialize(browsing_context, page = nil)
    @browsing_context = browsing_context
    @page = page
  end
end

# Page creates frame
Frame.new(@browsing_context, self)
```

**Problem**: Frame directly stores reference to Page, doesn't support nested frames (iframe).

### After (Correct - Following Puppeteer)

```ruby
class Frame
  def initialize(parent, browsing_context)
    @parent = parent  # Page or Frame
    @browsing_context = browsing_context
  end

  def page
    @parent.is_a?(Page) ? @parent : @parent.page
  end

  def parent_frame
    @parent.is_a?(Frame) ? @parent : nil
  end
end

# Page creates frame
Frame.new(self, @browsing_context)
```

**Benefits**:
- Supports nested frames (iframe within iframe)
- Matches Puppeteer's TypeScript implementation
- Enables recursive page traversal
- Simplifies parent_frame implementation

## Reference Implementation

Based on [Puppeteer's Frame.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Frame.ts):

```typescript
export class BidiFrame extends Frame {
  #parent: BidiPage | BidiFrame;
  #browsingContext: BrowsingContext;

  constructor(
    parent: BidiPage | BidiFrame,
    browsingContext: BrowsingContext,
  ) {
    super();
    this.#parent = parent;
    this.#browsingContext = browsingContext;
  }

  override get page(): BidiPage {
    let parent = this.#parent;
    while (parent instanceof BidiFrame) {
      parent = parent.#parent;
    }
    return parent;
  }

  override get parentFrame(): BidiFrame | null {
    if (this.#parent instanceof BidiFrame) {
      return this.#parent;
    }
    return null;
  }
}
```

## Implementation Details

### Constructor Signature

**Critical**: The first parameter is `parent` (Page or Frame), not `page`:

```ruby
def initialize(parent, browsing_context)
  @parent = parent
  @browsing_context = browsing_context
end
```

### Page Traversal

Recursive implementation using ternary operator:

```ruby
def page
  @parent.is_a?(Page) ? @parent : @parent.page
end
```

This is simpler than a while loop and matches Puppeteer's logic flow.

### Parent Frame Access

```ruby
def parent_frame
  @parent.is_a?(Frame) ? @parent : nil
end
```

Returns:
- `Frame` instance if this is a child frame
- `nil` if this is a main frame (parent is Page)

## Usage Examples

### Main Frame

```ruby
page = browser.new_page
main_frame = page.main_frame

main_frame.page         # => page
main_frame.parent_frame # => nil
```

### Nested Frames (Future)

```ruby
# When iframe support is added:
iframe = main_frame.child_frames.first

iframe.page         # => page (traverses up to Page)
iframe.parent_frame # => main_frame
```

## Testing

All 108 integration tests pass with this architecture:

```bash
bundle exec rspec spec/integration/
# 108 examples, 0 failures, 4 pending
```

## Key Takeaways

1. **Follow Puppeteer's constructor signature exactly** - `(parent, browsing_context)` not `(browsing_context, page)`
2. **Use ternary operator for simplicity** - `@parent.is_a?(Page) ? @parent : @parent.page`
3. **Enables future iframe support** - Architecture supports nested frame trees
4. **Remove redundant attr_reader** - No need for `attr_reader :parent` when using private instance variable

## Frame Events

### Overview

Frame lifecycle events are emitted on the Page object, following Puppeteer's pattern:

- `:frameattached` - Fired when a new child frame is created
- `:framedetached` - Fired when a frame's browsing context is closed
- `:framenavigated` - Fired on DOMContentLoaded or fragment navigation

### Event Emission Locations (Following Puppeteer Exactly)

**Critical**: The location where each event is emitted matters for correct behavior.

| Event | Location | Trigger |
|-------|----------|---------|
| `:frameattached` | `Frame#create_frame_target` | Child browsing context created |
| `:framedetached` | `Frame#initialize_frame` | **Self's** browsing context closed |
| `:framenavigated` | `Frame#initialize_frame` | DOMContentLoaded or fragment_navigated |

### Puppeteer Reference Code

From [Puppeteer's bidi/Frame.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Frame.ts):

```typescript
// In #initialize() - FrameDetached is emitted for THIS frame
this.browsingContext.on('closed', () => {
  this.page().trustedEmitter.emit(PageEvent.FrameDetached, this);
});

// In #createFrameTarget() - FrameAttached is emitted for child frame
#createFrameTarget(browsingContext: BrowsingContext) {
  const frame = BidiFrame.from(this, browsingContext);
  this.#frames.set(browsingContext, frame);
  this.page().trustedEmitter.emit(PageEvent.FrameAttached, frame);

  // Note: FrameDetached is NOT emitted here
  browsingContext.on('closed', () => {
    this.#frames.delete(browsingContext);
  });

  return frame;
}
```

### Ruby Implementation

```ruby
# Frame#initialize_frame
def initialize_frame
  # ... child frame setup ...

  # FrameDetached: emit when THIS frame's context closes
  @browsing_context.on(:closed) do
    @frames.clear
    page.emit(:framedetached, self)
  end

  # FrameNavigated: emit on navigation events
  @browsing_context.on(:dom_content_loaded) do
    page.emit(:framenavigated, self)
  end

  @browsing_context.on(:fragment_navigated) do
    page.emit(:framenavigated, self)
  end
end

# Frame#create_frame_target
def create_frame_target(browsing_context)
  frame = Frame.from(self, browsing_context)
  @frames[browsing_context.id] = frame

  # FrameAttached: emit for the new child frame
  page.emit(:frameattached, frame)

  # Only cleanup, NO FrameDetached here
  browsing_context.once(:closed) do
    @frames.delete(browsing_context.id)
  end

  frame
end
```

### Common Mistake

**Wrong**: Emitting `:framedetached` in `create_frame_target` when child's context closes.

**Correct**: Each frame emits its own `:framedetached` in `initialize_frame` when its own browsing context closes.

This matters because the event should be emitted by the frame instance that is being detached, not by its parent.

## Page Event Emitter

Page delegates to `Core::EventEmitter` for event handling:

```ruby
class Page
  def initialize(...)
    @emitter = Core::EventEmitter.new
  end

  def on(event, &block)
    @emitter.on(event, &block)
  end

  def emit(event, data = nil)
    @emitter.emit(event, data)
  end
end
```

## Files Changed

- `lib/puppeteer/bidi/frame.rb`: Constructor signature, page method, parent_frame method, frame events
- `lib/puppeteer/bidi/page.rb`: main_frame initialization, event emitter delegation

## BiDi Protocol Limitations

### Frame.frameElement with Shadow DOM

**Status**: Not supported in BiDi protocol

`Frame#frame_element` returns `nil` for iframes inside Shadow DOM (both open and closed).

#### Root Cause

| Protocol | Behavior | Mechanism |
|----------|----------|-----------|
| **CDP (Chrome)** | Works | Uses `DOM.getFrameOwner` command |
| **BiDi (Firefox)** | Returns nil | Uses `document.querySelectorAll` (cannot traverse Shadow DOM) |

#### Technical Details

1. **CDP Implementation** (`cdp/Frame.js`):
   ```javascript
   const { backendNodeId } = await parent.client.send('DOM.getFrameOwner', {
     frameId: this._id,
   });
   return await parent.mainRealm().adoptBackendNode(backendNodeId);
   ```

2. **BiDi Implementation** (base `api/Frame.js`):
   ```javascript
   const list = await parentFrame.isolatedRealm().evaluateHandle(() => {
     return document.querySelectorAll('iframe,frame');
   });
   // Cannot find elements inside Shadow DOM
   ```

3. **WebDriver BiDi Specification**: No `DOM.getFrameOwner` equivalent command exists.

#### Verification

Tested with Puppeteer (Node.js) using both protocols:

```
=== Firefox (BiDi protocol) ===
Frame element is NULL - Shadow DOM issue confirmed

=== Chrome (CDP protocol) ===
Frame element tagName: iframe
```

#### References

- [Puppeteer Issue #13155](https://github.com/puppeteer/puppeteer/issues/13155) - Original bug report
- [Puppeteer PR #13156](https://github.com/puppeteer/puppeteer/pull/13156) - CDP-only fix (October 2024)
- [WebDriver BiDi Specification](https://w3c.github.io/webdriver-bidi/) - browsingContext module

#### Test Status

```ruby
it 'should handle shadow roots', pending: 'BiDi protocol limitation: no DOM.getFrameOwner equivalent' do
  # ...
end
```

This is a **protocol limitation**, not an implementation bug in this library.

## Commit Reference

See commit: "Refactor Frame to use parent-based architecture following Puppeteer"

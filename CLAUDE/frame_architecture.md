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

## Files Changed

- `lib/puppeteer/bidi/frame.rb`: Constructor signature, page method, parent_frame method
- `lib/puppeteer/bidi/page.rb`: main_frame initialization (`Frame.new(self, @browsing_context)`)

## Commit Reference

See commit: "Refactor Frame to use parent-based architecture following Puppeteer"

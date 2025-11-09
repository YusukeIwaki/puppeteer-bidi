# Click Implementation and Mouse Input

This document provides comprehensive coverage of the click functionality implementation, including architecture, bug fixes, event handling, and BiDi protocol format requirements.

### Overview

Implemented full click functionality following Puppeteer's architecture, including mouse input actions, element visibility detection, and automatic scrolling.

### Architecture

```
Page#click
  ↓ delegates to
Frame#click
  ↓ delegates to
ElementHandle#click
  ↓ implementation
  1. scroll_into_view_if_needed
  2. clickable_point calculation
  3. Mouse#click (BiDi input.performActions)
```

### Key Components

#### Mouse Class (`lib/puppeteer/bidi/mouse.rb`)

Implements mouse input actions via BiDi `input.performActions`:

```ruby
def click(x, y, button: LEFT, count: 1, delay: nil)
  actions = []
  if @x != x || @y != y
    actions << {
      type: 'pointerMove',
      x: x.to_i,
      y: y.to_i,
      origin: 'viewport'  # BiDi expects string, not hash!
    }
  end
  @x = x
  @y = y
  bidi_button = button_to_bidi(button)
  count.times do
    actions << { type: 'pointerDown', button: bidi_button }
    actions << { type: 'pause', duration: delay.to_i } if delay
    actions << { type: 'pointerUp', button: bidi_button }
  end
  perform_actions(actions)
end
```

**Critical BiDi Protocol Detail**: The `origin` parameter must be the string `'viewport'`, NOT a hash like `{type: 'viewport'}`. This caused a protocol error during initial implementation.

#### ElementHandle Click Methods

##### scroll_into_view_if_needed

Uses IntersectionObserver API to detect viewport visibility:

```ruby
def scroll_into_view_if_needed
  return if intersecting_viewport?

  scroll_info = evaluate(<<~JS)
    element => {
      if (!element.isConnected) return 'Node is detached from document';
      if (element.nodeType !== Node.ELEMENT_NODE) return 'Node is not of type HTMLElement';

      element.scrollIntoView({
        block: 'center',
        inline: 'center',
        behavior: 'instant'
      });
      return false;
    }
  JS

  raise scroll_info if scroll_info
end
```

##### intersecting_viewport?

Uses browser's IntersectionObserver for accurate visibility detection:

```ruby
def intersecting_viewport?(threshold: 0)
  evaluate(<<~JS, threshold)
    (element, threshold) => {
      return new Promise(resolve => {
        const observer = new IntersectionObserver(entries => {
          resolve(entries[0].intersectionRatio > threshold);
          observer.disconnect();
        });
        observer.observe(element);
      });
    }
  JS
end
```

##### clickable_point

Calculates click coordinates with optional offset:

```ruby
def clickable_point(offset: nil)
  box = clickable_box
  if offset
    { x: box[:x] + offset[:x], y: box[:y] + offset[:y] }
  else
    { x: box[:x] + box[:width] / 2, y: box[:y] + box[:height] / 2 }
  end
end
```

### Critical Bug Fixes

#### 1. Missing session.subscribe Call

**Problem**: Navigation events (browsingContext.load, etc.) were not firing, causing tests to timeout.

**Root Cause**: Missing subscription to BiDi modules. Puppeteer subscribes to these modules on session creation:
- browsingContext
- network
- log
- script
- input

**Fix**: Added subscription in two places:

```ruby
# lib/puppeteer/bidi/browser.rb
subscribe_modules = %w[
  browsingContext
  network
  log
  script
  input
]
@session.subscribe(subscribe_modules)

# lib/puppeteer/bidi/core/session.rb
def initialize_session
  subscribe_modules = %w[
    browsingContext
    network
    log
    script
    input
  ]
  subscribe(subscribe_modules)
end
```

**Impact**: This fix enabled all navigation-related functionality, including the "click links which cause navigation" test.

#### 2. Event-Based URL Updates

**Problem**: Initial implementation updated `@url` directly in `navigate()` method, which is not how Puppeteer works.

**Puppeteer's Approach**: URL updates happen via BiDi events:
- `browsingContext.historyUpdated`
- `browsingContext.domContentLoaded`
- `browsingContext.load`

**Fix**: Removed direct URL assignment from navigate():

```ruby
# lib/puppeteer/bidi/core/browsing_context.rb
def navigate(url, wait: nil)
  raise BrowsingContextClosedError, @reason if closed?
  params = { context: @id, url: url }
  params[:wait] = wait if wait
  result = session.send_command('browsingContext.navigate', params)
  # URL will be updated via browsingContext.load event
  result
end
```

Event handlers (already implemented) update URL automatically:

```ruby
# History updated
session.on('browsingContext.historyUpdated') do |info|
  next unless info['context'] == @id
  @url = info['url']
  emit(:history_updated, nil)
end

# DOM content loaded
session.on('browsingContext.domContentLoaded') do |info|
  next unless info['context'] == @id
  @url = info['url']
  emit(:dom_content_loaded, nil)
end

# Page loaded
session.on('browsingContext.load') do |info|
  next unless info['context'] == @id
  @url = info['url']
  emit(:load, nil)
end
```

**Why this matters**: Event-based updates ensure URL synchronization even when navigation is triggered by user actions (like clicking links) rather than explicit `navigate()` calls.

### Test Coverage

#### Click Tests (20 tests in spec/integration/click_spec.rb)

Ported from [Puppeteer's click.spec.ts](https://github.com/puppeteer/puppeteer/blob/main/test/src/click.spec.ts):

1. **Basic clicking**: button, svg, wrapped links
2. **Edge cases**: window.Node removed, span with inline elements
3. **Navigation**: click after navigation, click links causing navigation
4. **Scrolling**: offscreen buttons, scrollable content
5. **Multi-click**: double click, triple click (text selection)
6. **Different buttons**: left, right (contextmenu), middle (auxclick)
7. **Visibility**: partially obscured button, rotated button
8. **Form elements**: checkbox toggle (input and label)
9. **Error handling**: missing selector
10. **Special cases**: disabled JavaScript, iframes (pending)

#### Page Tests (3 tests in spec/integration/page_spec.rb)

1. **Page.url**: Verify URL updates after navigation
2. **Page.setJavaScriptEnabled**: Control JavaScript execution (pending - Firefox limitation)

**All 108 integration tests pass** (4 pending due to Firefox BiDi limitations).

### Firefox BiDi Limitations

- `emulation.setScriptingEnabled`: Part of WebDriver BiDi spec but not yet implemented in Firefox
- Tests gracefully skip with clear messages using RSpec's `skip` feature

### Implementation Best Practices Learned

#### 1. Always Consult Puppeteer's Implementation First

**Workflow**:
1. Read Puppeteer's TypeScript implementation
2. Understand BiDi protocol calls being made
3. Implement Ruby equivalent with same logic flow
4. Port corresponding test cases

**Example**: The click implementation journey revealed that Puppeteer's architecture (Page → Frame → ElementHandle delegation) is critical for proper functionality.

#### 2. Stay Faithful to Puppeteer's Test Structure

**Initial mistake**: Created complex polling logic for navigation test
**Correction**: Simplified to match Puppeteer's simple approach:

```ruby
# Simple and correct (matches Puppeteer)
page.set_content("<a href=\"#{server.empty_page}\">empty.html</a>")
page.click('a')  # Should not hang
```

#### 3. Event Subscription is Critical

**Key lesson**: BiDi requires explicit subscription to event modules. Without it:
- Navigation events don't fire
- URL updates don't work
- Tests timeout mysteriously

**Solution**: Subscribe early in browser/session initialization.

#### 4. Use RSpec `it` Syntax

Per Ruby/RSpec conventions, use `it` instead of `example`:

```ruby
# Correct
it 'should click the button' do
  # ...
end

# Incorrect
example 'should click the button' do
  # ...
end
```

### BiDi Protocol Format Requirements

#### Origin Parameter Format

**Critical**: BiDi `input.performActions` expects `origin` as a string, not a hash:

```ruby
# CORRECT
origin: 'viewport'

# WRONG - causes protocol error
origin: { type: 'viewport' }
```

**Error message if wrong**:
```
Expected "origin" to be undefined, "viewport", "pointer", or an element,
got: [object Object] {"type":"viewport"}
```

### Performance and Reliability

- **IntersectionObserver**: Fast and accurate visibility detection
- **Auto-scrolling**: Ensures elements are clickable before interaction
- **Event-driven**: URL updates via events enable proper async handling
- **Thread-safe**: BiDi protocol handles concurrent operations naturally

### Future Enhancements

Potential improvements for click/mouse functionality:

1. **Drag and drop**: Implement drag operations
2. **Hover**: Mouse move without click
3. **Wheel**: Mouse wheel scrolling
4. **Touch**: Touch events for mobile emulation
5. **Keyboard modifiers**: Click with Ctrl/Shift/Alt
6. **Frame support**: Click inside iframes (currently pending)

### Reference Implementation

Based on Puppeteer's implementation:
- [Page.click](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Page.ts)
- [Frame.click](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Frame.ts)
- [ElementHandle.click](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts)
- [Mouse input](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Input.ts)
- [Test specs](https://github.com/puppeteer/puppeteer/blob/main/test/src/click.spec.ts)

### Key Takeaways

1. **session.subscribe is mandatory** for BiDi event handling - don't forget it!
2. **Event-based state management** (URL updates via events, not direct assignment)
3. **BiDi protocol details matter** (string vs hash for origin parameter)
4. **Follow Puppeteer's architecture** (delegation patterns, event handling)
5. **Test simplicity** - stay faithful to Puppeteer's test structure
6. **Browser limitations** - gracefully handle unimplemented features (setScriptingEnabled)


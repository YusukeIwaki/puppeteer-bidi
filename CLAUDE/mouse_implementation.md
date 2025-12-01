# Mouse Implementation

## Overview

Mouse input is implemented using WebDriver BiDi's `input.performActions` command with different source types.

## BiDi Input Sources

Different input types use different source types:

| Input Type | Source Type | Source ID |
|------------|-------------|-----------|
| Mouse pointer | `pointer` | `default mouse` |
| Keyboard | `key` | `default keyboard` |
| Mouse wheel | `wheel` | `__puppeteer_wheel` |

## Mouse Methods

### move(x, y, steps:)

Moves mouse to coordinates with optional intermediate steps for smooth movement.

```ruby
mouse.move(100, 200)           # Instant move
mouse.move(100, 200, steps: 5) # Smooth move with 5 intermediate points
```

Uses linear interpolation for intermediate positions.

### click(x, y, button:, count:, delay:)

Moves to coordinates and performs click(s).

```ruby
mouse.click(100, 200)                    # Single left click
mouse.click(100, 200, button: 'right')   # Right click
mouse.click(100, 200, button: 'middle')  # Middle click (aux click)
mouse.click(100, 200, button: 'back')    # Back button
mouse.click(100, 200, button: 'forward') # Forward button
mouse.click(100, 200, count: 2)          # Double click
mouse.click(100, 200, delay: 100)        # Click with 100ms delay between down/up
```

### wheel(delta_x:, delta_y:)

Scrolls using mouse wheel at current mouse position.

```ruby
mouse.wheel(delta_y: -100)  # Scroll up
mouse.wheel(delta_y: 100)   # Scroll down
mouse.wheel(delta_x: 50)    # Scroll right
```

**Important**: Uses separate `wheel` source type (not `pointer`).

### reset

Resets mouse state to origin and releases all pressed buttons.

```ruby
mouse.reset
```

Uses `input.releaseActions` BiDi command.

## Data Classes

### ElementHandle::BoundingBox

```ruby
BoundingBox = Data.define(:x, :y, :width, :height)

box = element.bounding_box
box.x      # => 10.0
box.width  # => 100.0
```

### ElementHandle::Point

```ruby
Point = Data.define(:x, :y)

point = element.clickable_point
point.x  # => 50.0
point.y  # => 75.0
```

### ElementHandle::BoxModel

CSS box model with content, padding, border, and margin quads. Each quad is an array of 4 Points (top-left, top-right, bottom-right, bottom-left).

```ruby
BoxModel = Data.define(:content, :padding, :border, :margin, :width, :height)

box = element.box_model
box.width           # => 200.0
box.height          # => 100.0
box.border[0]       # => Point(x: 10.0, y: 20.0) - top-left corner
box.content[0].x    # => 21.0 (border.x + borderLeftWidth + paddingLeft)
```

**Note**: Frame offset handling is not yet implemented. For elements inside iframes, coordinates are relative to the iframe, not the main page.

## ElementHandle#click

ElementHandle has its own `click` method that:
1. Scrolls element into view if needed
2. Gets clickable point
3. Uses `frame.page.mouse.click()` to perform the click

```ruby
element = page.query_selector('button')
element.click                      # Single click
element.click(count: 2)            # Double click
element.click(button: 'right')     # Right click
```

Note: ElementHandle gets its frame via `@realm.environment`, so no frame parameter is needed.

## Hover Implementation

Hover is implemented at three levels following Puppeteer's pattern:

1. **ElementHandle#hover** - Scrolls into view, gets clickable point, moves mouse
2. **Frame#hover(selector)** - Queries element, calls element.hover
3. **Page#hover(selector)** - Delegates to main_frame.hover

## WebDriver BiDi Limitations

### is_mobile not supported

The `set_viewport` method does not support `is_mobile` parameter because WebDriver BiDi protocol doesn't support device emulation yet.

- Tracking issue: https://github.com/w3c/webdriver-bidi/issues/772
- Puppeteer also doesn't implement this for BiDi

## References

- [WebDriver BiDi Input Module](https://w3c.github.io/webdriver-bidi/#module-input)
- [Puppeteer Input.ts](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Input.ts)

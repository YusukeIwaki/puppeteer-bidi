# Wrapped Element Click Implementation

## Problem

When clicking on wrapped or multi-line text elements, using `getBoundingClientRect()` returns a single large bounding box that may have empty space in the center, causing clicks to miss the actual element.

## Example: Wrapped Link

```html
<div style="width: 10ch; word-wrap: break-word;">
  <a href='#clicked'>123321</a>
</div>
```

The link text wraps into two lines:
```
123
321
```

### getBoundingClientRect() Problem

Returns single large box:
```ruby
{x: 628.45, y: 62.47, width: 109.1, height: 49.73}
```

Click point (center): `(683, 87)` → **hits empty space between lines!**

### getClientRects() Solution

Returns multiple boxes for wrapped text:
```ruby
[
  {x: 708.58, y: 62.47, width: 32.73, height: 22.67},  # "123"
  {x: 628.45, y: 85.15, width: 32.73, height: 22.67}   # "321"
]
```

Click point (first box center): `(725, 73)` → **hits actual text!**

## Implementation

### clickable_box Method

```ruby
def clickable_box
  assert_not_disposed

  # Get client rects - returns multiple boxes for wrapped elements
  boxes = evaluate(<<~JS)
    element => {
      if (!(element instanceof Element)) {
        return null;
      }
      return [...element.getClientRects()].map(rect => {
        return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
      });
    }
  JS

  return nil unless boxes&.is_a?(Array) && !boxes.empty?

  # Intersect boxes with frame boundaries
  intersect_bounding_boxes_with_frame(boxes)

  # Find first box with valid dimensions
  box = boxes.find { |rect| rect['width'] >= 1 && rect['height'] >= 1 }
  return nil unless box

  {
    x: box['x'],
    y: box['y'],
    width: box['width'],
    height: box['height']
  }
end
```

### Viewport Clipping: intersectBoundingBoxesWithFrame

Clips element boxes to visible viewport boundaries:

```ruby
def intersect_bounding_boxes_with_frame(boxes)
  # Get document dimensions using element's evaluate
  dimensions = evaluate(<<~JS)
    element => {
      return {
        documentWidth: element.ownerDocument.documentElement.clientWidth,
        documentHeight: element.ownerDocument.documentElement.clientHeight
      };
    }
  JS

  document_width = dimensions['documentWidth']
  document_height = dimensions['documentHeight']

  boxes.each do |box|
    intersect_bounding_box(box, document_width, document_height)
  end
end

def intersect_bounding_box(box, width, height)
  # Clip width
  box['width'] = [
    box['x'] >= 0 ?
      [width - box['x'], box['width']].min :
      [width, box['width'] + box['x']].min,
    0
  ].max

  # Clip height
  box['height'] = [
    box['y'] >= 0 ?
      [height - box['y'], box['height']].min :
      [height, box['height'] + box['y']].min,
    0
  ].max

  # Ensure non-negative coordinates
  box['x'] = [box['x'], 0].max
  box['y'] = [box['y'], 0].max
end
```

## Why This Matters

### Use Cases for getClientRects()

1. **Wrapped text**: Multi-line links, buttons with text wrapping
2. **Inline elements**: `<span>` elements that span multiple lines
3. **Complex layouts**: Elements with transforms, rotations

### Algorithm Flow

1. **Get all client rects** for element (array of boxes)
2. **Clip to viewport** using intersectBoundingBox algorithm
3. **Find first valid box** (width >= 1 && height >= 1)
4. **Click center of that box**

## Puppeteer Reference

Based on [ElementHandle.ts#clickableBox](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts):

```typescript
async #clickableBox(): Promise<BoundingBox | null> {
  const boxes = await this.evaluate(element => {
    if (!(element instanceof Element)) {
      return null;
    }
    return [...element.getClientRects()].map(rect => {
      return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
    });
  });

  if (!boxes?.length) {
    return null;
  }

  await this.#intersectBoundingBoxesWithFrame(boxes);

  // ... parent frame handling ...

  const box = boxes.find(box => {
    return box.width >= 1 && box.height >= 1;
  });

  return box || null;
}
```

## Testing

### Test Asset

Official Puppeteer test asset: `spec/assets/wrappedlink.html`

```html
<div style="width: 10ch; word-wrap: break-word; transform: rotate(33deg);">
  <a href='#clicked'>123321</a>
</div>
```

**Critical**: Always use official test assets without modification!

### Test Case

```ruby
it 'should click wrapped links' do
  with_test_state do |page:, server:, **|
    page.goto("#{server.prefix}/wrappedlink.html")
    page.click('a')
    result = page.evaluate('window.__clicked')
    expect(result).to be true
  end
end
```

## Debugging Protocol Messages

Compare BiDi protocol messages with Puppeteer to verify coordinates:

```bash
# Ruby implementation
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/click_spec.rb:138

# Look for input.performActions with click coordinates
# Verify they fall within actual element bounds
```

## Key Takeaways

1. **getClientRects() > getBoundingClientRect()** for clickable elements
2. **First valid box** is the click target (not center of bounding box)
3. **Viewport clipping** ensures clicks stay within visible area
4. **Test with official assets** - simplified versions hide edge cases
5. **Follow Puppeteer exactly** - algorithm has been battle-tested

## Performance

- `getClientRects()` is fast (native browser API)
- Intersection algorithm is O(n) where n = number of boxes (typically 1-3)
- No additional round-trips to browser

## Future: Parent Frame Support

For iframe support, add coordinate transformation:

```ruby
# TODO: Handle parent frames
frame = self.frame
while (parent_frame = frame.parent_frame)
  # Adjust coordinates for parent frame offset
  # boxes.each { |box| box['x'] += offset_x; box['y'] += offset_y }
end
```

## Files

- `lib/puppeteer/bidi/element_handle.rb`: clickable_box, intersect methods
- `spec/integration/click_spec.rb`: Test case for wrapped links
- `spec/assets/wrappedlink.html`: Official test asset (never modify!)

## Commit Reference

See commit: "Implement clickable_box with getClientRects() and viewport clipping"

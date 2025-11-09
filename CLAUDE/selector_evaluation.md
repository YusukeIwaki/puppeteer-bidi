# Selector Evaluation Methods Implementation

This document explains the implementation of `eval_on_selector` and `eval_on_selector_all` methods, including delegation patterns, handle lifecycle, and performance considerations.

### Overview

The `eval_on_selector` and `eval_on_selector_all` methods provide convenient shortcuts for querying elements and evaluating JavaScript functions on them, equivalent to Puppeteer's `$eval` and `$$eval`.

### API Design

#### Method Naming Convention

Ruby cannot use `$` in method names, so we use descriptive alternatives:

| Puppeteer | Ruby | Description |
|-----------|------|-------------|
| `$eval` | `eval_on_selector` | Evaluate on first matching element |
| `$$eval` | `eval_on_selector_all` | Evaluate on all matching elements |

#### Implementation Hierarchy

Following Puppeteer's delegation pattern:

```
Page#eval_on_selector(_all)
  ↓ delegates to
Frame#eval_on_selector(_all)
  ↓ delegates to
ElementHandle#eval_on_selector(_all) (on document)
  ↓ implementation
  1. query_selector(_all) - Find element(s)
  2. Validate results
  3. evaluate() - Execute function
  4. dispose - Clean up handles
```

### Implementation Details

#### Page and Frame Methods

```ruby
# lib/puppeteer/bidi/page.rb
def eval_on_selector(selector, page_function, *args)
  main_frame.eval_on_selector(selector, page_function, *args)
end

# lib/puppeteer/bidi/frame.rb
def eval_on_selector(selector, page_function, *args)
  document.eval_on_selector(selector, page_function, *args)
end
```

**Design rationale**: Page and Frame act as thin wrappers, delegating to the document element handle.

#### ElementHandle#eval_on_selector

```ruby
def eval_on_selector(selector, page_function, *args)
  assert_not_disposed

  element_handle = query_selector(selector)
  raise SelectorNotFoundError, selector unless element_handle

  begin
    element_handle.evaluate(page_function, *args)
  ensure
    element_handle.dispose
  end
end
```

**Key points**:
- Throws `SelectorNotFoundError` if no element found (matches Puppeteer behavior)
- Uses `begin/ensure` to guarantee handle disposal
- Searches within element's subtree (not page-wide)

#### ElementHandle#eval_on_selector_all

```ruby
def eval_on_selector_all(selector, page_function, *args)
  assert_not_disposed

  element_handles = query_selector_all(selector)

  begin
    # Create array handle in browser context
    array_handle = @realm.call_function(
      '(...elements) => elements',
      false,
      arguments: element_handles.map(&:remote_value)
    )

    array_js_handle = JSHandle.from(array_handle['result'], @realm)

    begin
      array_js_handle.evaluate(page_function, *args)
    ensure
      array_js_handle.dispose
    end
  ensure
    element_handles.each(&:dispose)
  end
end
```

**Key points**:
- Returns result for empty array without error (differs from `eval_on_selector`)
- Creates array handle using spread operator trick: `(...elements) => elements`
- Nested `ensure` blocks for proper resource cleanup
- Disposes both individual element handles and array handle

### Error Handling Differences

| Method | Behavior when no elements found |
|--------|--------------------------------|
| `eval_on_selector` | Throws `SelectorNotFoundError` |
| `eval_on_selector_all` | Returns evaluation result (e.g., `0` for `divs => divs.length`) |

This matches Puppeteer's behavior:
- `$eval`: Must find exactly one element
- `$$eval`: Works with zero or more elements

### Usage Examples

```ruby
# Basic usage
page.set_content('<section id="test">Hello</section>')
id = page.eval_on_selector('section', 'e => e.id')
# => "test"

# With arguments
text = page.eval_on_selector('section', '(e, suffix) => e.textContent + suffix', '!')
# => "Hello!"

# ElementHandle arguments
div = page.query_selector('div')
result = page.eval_on_selector('section', '(e, div) => e.textContent + div.textContent', div)

# eval_on_selector_all with multiple elements
page.set_content('<div>A</div><div>B</div><div>C</div>')
count = page.eval_on_selector_all('div', 'divs => divs.length')
# => 3

# Subtree search with ElementHandle
tweet = page.query_selector('.tweet')
likes = tweet.eval_on_selector('.like', 'node => node.innerText')
# Only searches within .tweet element
```

### Test Coverage

**Total**: 13 integration tests

**Page.eval_on_selector** (4 tests):
- Basic functionality (property access)
- Argument passing
- ElementHandle arguments
- Error on missing selector

**ElementHandle.eval_on_selector** (3 tests):
- Basic functionality
- Subtree isolation
- Error on missing selector

**Page.eval_on_selector_all** (4 tests):
- Basic functionality (array length)
- Extra arguments
- ElementHandle arguments
- Large element count (1001 elements)

**ElementHandle.eval_on_selector_all** (2 tests):
- Subtree retrieval
- Empty result handling

### Performance Considerations

#### Handle Lifecycle

- **eval_on_selector**: Creates 1 temporary handle per call
- **eval_on_selector_all**: Creates N+1 handles (N elements + 1 array)
- All handles automatically disposed after evaluation

#### Large Element Sets

Tested with 1001 elements without issues. The implementation efficiently:
1. Queries all elements at once
2. Creates single array handle
3. Evaluates function in single round-trip
4. Disposes all handles in parallel

### Reference Implementation

Based on Puppeteer's implementation:
- [Page.$eval](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Page.ts)
- [Frame.$eval](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Frame.ts)
- [ElementHandle.$eval](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts)
- [Test specs](https://github.com/puppeteer/puppeteer/blob/main/test/src/queryselector.spec.ts)


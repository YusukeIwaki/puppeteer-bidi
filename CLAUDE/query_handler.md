# QueryHandler Implementation

The QueryHandler system provides extensible selector handling for CSS, XPath, text, and other selector types.

## Architecture

```
QueryHandler (singleton)
├── get_query_handler_and_selector(selector)
│   └── Returns: { updated_selector, polling, query_handler }

BaseQueryHandler
├── run_query_one(element, selector)  → ElementHandle | nil
├── run_query_all(element, selector)  → Array<ElementHandle>
└── wait_for(element_or_frame, selector, options)

Implementations:
├── CSSQueryHandler   - Default, uses cssQuerySelector/cssQuerySelectorAll
├── XPathQueryHandler - xpath/ prefix, uses xpathQuerySelectorAll
└── TextQueryHandler  - text/ prefix, uses textQuerySelectorAll
```

## Selector Prefixes

| Prefix    | Handler            | Example                     |
| --------- | ------------------ | --------------------------- |
| (none)    | CSSQueryHandler    | `div.foo`, `#id`            |
| `xpath/`  | XPathQueryHandler  | `xpath/html/body/div`       |
| `text/`   | TextQueryHandler   | `text/Hello World`          |
| `aria/`   | ARIAQueryHandler   | `aria/Submit[role="button"]`|
| `pierce/` | PierceQueryHandler | `pierce/.shadow-element`    |

## Implementation Pattern

All query handlers follow the same pattern: override `query_one_script`, `query_all_script`, and `wait_for_selector_script` to define the JavaScript that runs in the browser.

```ruby
class CSSQueryHandler < BaseQueryHandler
  private

  def query_one_script
    <<~JAVASCRIPT
    (PuppeteerUtil, element, selector) => {
      return PuppeteerUtil.cssQuerySelector(element, selector);
    }
    JAVASCRIPT
  end

  def query_all_script
    <<~JAVASCRIPT
    async (PuppeteerUtil, element, selector) => {
      return [...PuppeteerUtil.cssQuerySelectorAll(element, selector)];
    }
    JAVASCRIPT
  end

  def wait_for_selector_script
    <<~JAVASCRIPT
    (PuppeteerUtil, selector, root, visibility) => {
      const element = PuppeteerUtil.cssQuerySelector(root || document, selector);
      return PuppeteerUtil.checkVisibility(element, visibility === null ? undefined : visibility);
    }
    JAVASCRIPT
  end
end
```

## TextQueryHandler - Special Case

`textQuerySelectorAll` cannot be extracted via `toString()` because it references helper functions (`f`, `m`, `d`) that are only available within the PuppeteerUtil closure. So TextQueryHandler uses a different pattern: call `textQuerySelectorAll` directly from PuppeteerUtil instead of recreating the function.

```ruby
class TextQueryHandler < BaseQueryHandler
  private

  def query_one_script
    <<~JAVASCRIPT
    (PuppeteerUtil, element, selector) => {
      for (const result of PuppeteerUtil.textQuerySelectorAll(element, selector)) {
        return result;
      }
      return null;
    }
    JAVASCRIPT
  end

  def query_all_script
    <<~JAVASCRIPT
    async (PuppeteerUtil, element, selector) => {
      return [...PuppeteerUtil.textQuerySelectorAll(element, selector)];
    }
    JAVASCRIPT
  end
end
```

## Handle Adoption Pattern

After navigation, the sandbox realm is destroyed and `puppeteer_util` handles become stale. The solution is to adopt the element into the isolated realm BEFORE calling any query methods:

```ruby
def run_query_one(element, selector)
  realm = element.frame.isolated_realm

  # Adopt the element into the isolated realm first.
  # This ensures the realm is valid and triggers puppeteer_util reset if needed
  # after navigation (mirrors Puppeteer's @bindIsolatedHandle decorator pattern).
  adopted_element = realm.adopt_handle(element)

  result = realm.call_function(
    query_one_script,
    false,
    arguments: [
      Serializer.serialize(realm.puppeteer_util_lazy_arg),
      adopted_element.remote_value,
      Serializer.serialize(selector)
    ]
  )

  # ... handle result ...
ensure
  adopted_element&.dispose
end
```

**Why this matters:**

1. After navigation, sandbox realm is destroyed
2. `:updated` event that resets `puppeteer_util` isn't fired until we call INTO the sandbox
3. Calling `adopt_handle` first ensures the realm exists and is valid
4. Then `puppeteer_util` will be fresh (re-evaluated if realm was recreated)

## Debugging

Use `DEBUG_BIDI_COMMAND=1` to see protocol messages:

```bash
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/queryhandler_spec.rb:8
```

This shows:
1. PuppeteerUtil being evaluated in sandbox
2. The query function being called with arguments
3. The result being returned

## Adding New Query Handlers

1. Create a new class extending `BaseQueryHandler`
2. Override `query_one_script`, `query_all_script`, and `wait_for_selector_script`
3. Register in `BUILTIN_QUERY_HANDLERS` constant
4. The script receives `(PuppeteerUtil, element, selector)` as arguments
5. Return the element(s) found or null/empty array

```ruby
class MyQueryHandler < BaseQueryHandler
  private

  def query_one_script
    <<~JAVASCRIPT
    (PuppeteerUtil, element, selector) => {
      // Use PuppeteerUtil.myQuerySelector if available
      // Or implement custom logic
      return element.querySelector(selector);
    }
    JAVASCRIPT
  end

  def query_all_script
    <<~JAVASCRIPT
    async (PuppeteerUtil, element, selector) => {
      return [...element.querySelectorAll(selector)];
    }
    JAVASCRIPT
  end

  def wait_for_selector_script
    <<~JAVASCRIPT
    (PuppeteerUtil, selector, root, visibility) => {
      const element = (root || document).querySelector(selector);
      return PuppeteerUtil.checkVisibility(element, visibility === null ? undefined : visibility);
    }
    JAVASCRIPT
  end
end
```

## Test Coverage

Tests are in `spec/integration/queryhandler_spec.rb`:

- Text selectors: 12 tests (query_selector, query_selector_all, shadow DOM piercing, etc.)
- XPath selectors: 6 tests (in Page and ElementHandle)

Tests ported from Puppeteer's `test/src/queryhandler.spec.ts`.

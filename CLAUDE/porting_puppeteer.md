# Porting Puppeteer to Ruby

Best practices for implementing Puppeteer features in puppeteer-bidi.

## 1. Reference Implementation First

**Always consult the official Puppeteer implementation before implementing features:**

- **TypeScript source files**:
  - `packages/puppeteer-core/src/bidi/Page.ts` - High-level Page API
  - `packages/puppeteer-core/src/bidi/BrowsingContext.ts` - Core BiDi context
  - `packages/puppeteer-core/src/api/Page.ts` - Common Page interface

- **Test files**:
  - `test/src/screenshot.spec.ts` - Screenshot test suite
  - `test/golden-firefox/` - Golden images for visual regression testing

**Example workflow:**

```ruby
# 1. Read Puppeteer's TypeScript implementation
# 2. Understand the BiDi protocol calls being made
# 3. Implement Ruby equivalent with same logic flow
# 4. Port corresponding test cases
```

## 2. Test Infrastructure Setup

**Use async-http for test servers** (lightweight + Async-friendly):

```ruby
# spec/support/test_server.rb
endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{@port}")

server = Async::HTTP::Server.for(endpoint) do |request|
  if handler = lookup_route(request.path)
    notify_request(request.path)
    respond_with_handler(handler, request)
  else
    serve_static_asset(request)
  end
end

server.run
```

**Helper pattern for integration tests:**

```ruby
# Optimized helper - reuses shared browser, creates new page per test
def with_test_state
  page = $shared_browser.new_page
  context = $shared_browser.default_browser_context

  begin
    yield(page: page, server: $shared_test_server, browser: $shared_browser, context: context)
  ensure
    page.close unless page.closed?
  end
end
```

## 3. BiDi Protocol Data Deserialization

**BiDi returns values in special format - always deserialize:**

```ruby
# BiDi response format:
# [["width", {"type" => "number", "value" => 500}],
#  ["height", {"type" => "number", "value" => 1000}]]

def deserialize_result(result)
  value = result['value']
  return value unless value.is_a?(Array)

  # Convert to Ruby Hash
  if value.all? { |item| item.is_a?(Array) && item.length == 2 }
    value.each_with_object({}) do |(key, val), hash|
      hash[key] = deserialize_value(val)
    end
  else
    value
  end
end

def deserialize_value(val)
  case val['type']
  when 'number' then val['value']
  when 'string' then val['value']
  when 'boolean' then val['value']
  when 'undefined', 'null' then nil
  else val['value']
  end
end
```

## 4. Implementing Puppeteer-Compatible APIs

**Follow Puppeteer's exact logic flow:**

Example: `fullPage` screenshot implementation

```ruby
# From Puppeteer's Page.ts:
# if (options.fullPage) {
#   if (!options.captureBeyondViewport) {
#     // Resize viewport to full page
#   }
# } else {
#   options.captureBeyondViewport = false;
# }

if full_page
  unless capture_beyond_viewport
    scroll_dimensions = evaluate(...)
    set_viewport(scroll_dimensions)
    begin
      data = capture_screenshot(origin: 'viewport')
    ensure
      set_viewport(original_viewport)  # Always restore
    end
  else
    options[:origin] = 'document'
  end
elsif !clip
  capture_beyond_viewport = false  # Match Puppeteer behavior
end
```

**Key principles:**

- Use `begin/ensure` blocks for cleanup (viewport restoration, etc.)
- Match Puppeteer's parameter defaults exactly
- Follow the same conditional logic order

## 5. Layer Architecture

**Maintain clear separation:**

```
High-level API (lib/puppeteer/bidi/)
├── Browser        - User-facing browser interface
├── BrowserContext - Session management
└── Page           - Page automation API

Core Layer (lib/puppeteer/bidi/core/)
├── Session        - BiDi session management
├── Browser        - Low-level browser operations
├── UserContext    - BiDi user context
└── BrowsingContext - BiDi browsing context (tab/frame)
```

## 6. Setting Page Content

**Use data URLs with base64 encoding:**

```ruby
def set_content(html, wait_until: 'load')
  # Encode HTML in base64 to avoid URL encoding issues
  encoded = Base64.strict_encode64(html)
  data_url = "data:text/html;base64,#{encoded}"
  goto(data_url, wait_until: wait_until)
end
```

**Why base64:**

- Avoids URL encoding issues with special characters
- Handles multi-byte characters correctly
- Standard approach in browser automation tools

## 7. Viewport Restoration

**Always restore viewport after temporary changes:**

```ruby
# Save current viewport (may be nil)
original_viewport = viewport

# If no viewport set, save window size
unless original_viewport
  original_size = evaluate('({ width: window.innerWidth, height: window.innerHeight })')
  original_viewport = { width: original_size['width'].to_i, height: original_size['height'].to_i }
end

# Change viewport temporarily
set_viewport(width: new_width, height: new_height)

begin
  # Do work
ensure
  # Always restore
  set_viewport(**original_viewport) if original_viewport
end
```

## 8. Test Assets Policy

**CRITICAL**: Always use Puppeteer's official test assets without modification.

- **Source**: https://github.com/puppeteer/puppeteer/tree/main/test/assets
- **Rule**: Never modify test asset files (HTML, CSS, images) in `spec/assets/`
- **Verification**: Before creating PR, verify all `spec/assets/` files match Puppeteer's official versions

```bash
# During development - OK to experiment
vim spec/assets/test.html  # Temporary modification for debugging

# Before PR - MUST revert to official
curl -sL https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/assets/test.html \
  -o spec/assets/test.html
```

**Why this matters**: Test assets are designed to test specific edge cases (rotated elements, complex layouts, etc.). Using simplified versions defeats the purpose of these tests.

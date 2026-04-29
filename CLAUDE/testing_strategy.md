# Testing Strategy and Performance Optimization

This document covers integration test organization, performance optimization strategies, golden image testing, and debugging techniques.


#### Integration Tests Organization

```
spec/
└── unit/                    # Fast unit tests (future)

smartest/
├── assets/                 # Browser test HTML/CSS/JS files
│   ├── grid.html
│   ├── scrollbar.html
│   ├── empty.html
│   └── digits/*.png
├── golden-firefox/         # Reference images
│   └── screenshot-*.png
├── fixtures/               # Browser, server, page, and cookie-state fixtures
├── matchers/               # Smartest matcher extensions used by browser tests
├── support/                # Browser-test utilities
│   ├── test_server.rb
│   ├── golden_comparator.rb
│   └── cookie_helpers.rb
└── integration/            # Browser automation tests
    ├── examples/           # Example-based tests
    └── screenshot_test.rb  # Feature test suites
```

#### Implemented Screenshot Tests

All 12 tests ported from [Puppeteer's screenshot.spec.ts](https://github.com/puppeteer/puppeteer/blob/main/test/src/screenshot.spec.ts):

1. **should work** - Basic screenshot functionality
2. **should clip rect** - Clipping specific region
3. **should get screenshot bigger than the viewport** - Offscreen clip with captureBeyondViewport
4. **should clip bigger than the viewport without "captureBeyondViewport"** - Viewport coordinate transformation
5. **should run in parallel** - Thread-safe parallel screenshots on single page
6. **should take fullPage screenshots** - Full page with document origin
7. **should take fullPage screenshots without captureBeyondViewport** - Full page with viewport resize
8. **should run in parallel in multiple pages** - Concurrent screenshots across multiple pages
9. **should work with odd clip size on Retina displays** - Odd pixel dimensions (11x11)
10. **should return base64** - Base64 encoding verification
11. **should take fullPage screenshots when defaultViewport is null** - No explicit viewport
12. **should restore to original viewport size** - Viewport restoration after fullPage

Run tests:
```bash
bundle exec smartest smartest/integration/screenshot_test.rb
# Expected: 12 tests, 0 failures (completes in ~8 seconds with shared browser fixtures)
```

#### Test Performance Optimization

**Critical**: Integration tests are ~19x faster with browser reuse strategy.

##### Before Optimization (Per-test Browser Launch)
```ruby
def with_test_state(**options)
  server = TestServer::Server.new
  server.start

  with_browser(**options) do |browser|  # New browser per test!
    context = browser.default_browser_context
    page = browser.new_page
    yield(page: page, server: server, browser: browser, context: context)
  end
ensure
  server.stop
end
```

**Performance**: ~195 seconds for 35 tests (browser launch overhead × 35)

##### After Optimization (Shared Browser)
```ruby
# In smartest/fixtures/browser_fixture.rb
suite_fixture :browser do
  BrowserTestResources.start
  BrowserTestResources.browser
end

fixture :page do |browser:|
  page = browser.new_page
  cleanup { page.close unless page.closed? }
  page
end

fixture :server do |test_server:|
  cleanup { test_server.clear_routes }
  test_server
end
```

**Performance**: ~10 seconds for 35 tests (1 browser launch + 35 tab creations)

##### Performance Results

| Test Suite | Before | After | Improvement |
|------------|--------|-------|-------------|
| **evaluation_test (23 tests)** | 127s | **7.17s** | **17.7x faster** |
| **screenshot_test (12 tests)** | 68s | **8.47s** | **8.0x faster** |
| **Combined (35 tests)** | 195s | **10.33s** | **18.9x faster** 🚀 |

**Key Benefits**:
- Browser launch only once per suite
- Each test gets fresh page (tab) for isolation
- Cleanup handled automatically
- Backward compatible (custom options fall back to per-test browser)

#### Environment Variables

```bash
HEADLESS=false  # Run browser in non-headless mode for debugging
```

### Debugging Techniques

#### 1. Save Screenshots for Inspection

```ruby
# In smartest/support/golden_comparator.rb
def save_screenshot(screenshot_base64, filename)
  output_dir = File.join(__dir__, '../output')
  FileUtils.mkdir_p(output_dir)
  File.binwrite(File.join(output_dir, filename),
                Base64.decode64(screenshot_base64))
end
```

#### 2. Compare Images Pixel-by-Pixel

```ruby
cat > /tmp/compare.rb << 'EOF'
require 'chunky_png'

golden = ChunkyPNG::Image.from_file('smartest/golden-firefox/screenshot.png')
actual = ChunkyPNG::Image.from_file('spec/output/debug.png')

diff_count = 0
(0...golden.height).each do |y|
  (0...golden.width).each do |x|
    if golden[x, y] != actual[x, y]
      diff_count += 1
      puts "Diff at (#{x}, #{y})" if diff_count <= 10
    end
  end
end
puts "Total: #{diff_count} pixels differ"
EOF
ruby /tmp/compare.rb
```

#### 3. Debug BiDi Responses

```ruby
# Temporarily add debugging
result = @browsing_context.default_realm.evaluate(script, true)
puts "BiDi result: #{result.inspect}"
deserialize_result(result)
```

### Common Pitfalls and Solutions

#### 1. BiDi Protocol Differences

**Problem:** BiDi `origin` parameter behavior differs from expectations

**Solution:** Consult BiDi spec and test both `'document'` and `'viewport'` origins

```ruby
# document: Absolute coordinates in full page
# viewport: Relative to current viewport
options[:origin] = capture_beyond_viewport ? 'document' : 'viewport'
```

#### 2. Image Comparison Failures

**Problem:** Golden images don't match exactly (1-2 pixel differences)

**Solution:** Implement tolerance in comparison

```ruby
# Allow small rendering differences (±1 RGB per channel)
compare_with_golden(screenshot, 'golden.png', pixel_threshold: 1)
```

#### 3. Viewport State Management

**Problem:** Viewport not restored after fullPage screenshot

**Solution:** Use `ensure` block

```ruby
begin
  set_viewport(full_page_dimensions)
  screenshot = capture_screenshot(...)
ensure
  set_viewport(original_viewport) if original_viewport
end
```

#### 4. Thread Safety

**Problem:** Parallel screenshots cause race conditions

**Solution:** BiDi protocol handles this naturally - test with threads

```ruby
threads = (0...3).map do |i|
  Thread.new { page.screenshot(clip: {...}) }
end
screenshots = threads.map(&:value)
```

### Documentation References

**Essential reading for implementation:**

1. **WebDriver BiDi Spec**: https://w3c.github.io/webdriver-bidi/
2. **Puppeteer Source**: https://github.com/puppeteer/puppeteer
3. **Puppeteer BiDi Tests**: https://github.com/puppeteer/puppeteer/tree/main/test/src
4. **Firefox BiDi Impl**: Check Firefox implementation notes for quirks

**Reference implementation workflow:**
1. Find corresponding Puppeteer test in `test/src/`
2. Read TypeScript implementation in `packages/puppeteer-core/src/`
3. Check BiDi spec for protocol details
4. Implement Ruby version maintaining same logic
5. Download golden images and verify pixel-perfect match (with tolerance)

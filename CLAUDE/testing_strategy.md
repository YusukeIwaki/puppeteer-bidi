# Testing Strategy and Performance Optimization

This document covers integration test organization, performance optimization strategies, golden image testing, and debugging techniques.

## Upstream Test Fidelity

For ports, use the behavior/test mapping in the [porting guide](porting_puppeteer.md). Read the full upstream test
body, setup/teardown, fixtures, and expectation conditions at the chosen ref. A matching test title or a passing
assertion about a related helper is not a faithful port.

- Preserve inputs, options, assertions, and their order, including negative assertions, unresolved/pending states,
  timeout behavior, repeated or concurrent calls, and cleanup. If upstream first asserts that a waiter stays
  unresolved and then triggers a mutation, retaining only the final result loses the regression being tested.
- Preserve timing relationships. Use deterministic synchronization when it tests the same condition; removing a
  delay or replacing it with a final-value assertion requires evidence that the original race is still covered.
- Keep complete runnable test bodies for justified pending/skipped examples. Do not replace them with an empty
  block or a reason string. Follow the [pending/skip policy](rspec_pending_vs_skip.md), including platform and
  browser-version conditions, and account for every excluded case in the mapping.
- Use official fixtures from the selected upstream ref. Do not remove difficult selectors, shadow roots, frames,
  or other triggering structure to accommodate missing Ruby support. Implement in-scope prerequisites.
- Exercise the public entry point and relevant construction paths, not only a directly constructed internal
  object. Test option/logger propagation to descendants, payload omission/defaults, and disabled behavior when
  those contracts change.
- Match the boundary upstream tests exercise. A real WebSocket test must observe actual peer frames, liveness,
  timeout, and close behavior as applicable; counting `send_ping` calls or invoking a pong callback directly does
  not verify flushing or delivery. File/stream tests should observe actual contents, events, permissions, and
  errors where relevant, rather than only checking method calls or listener registration.
- Unit doubles and fault injection are useful supplements. Inspect the actual dependency version and inject a
  failure at a boundary that can produce it; do not invent exception, flush, or close semantics to make a mock pass.
  Keep real-boundary coverage when dependency semantics are part of the regression.

For each relevant regression, explain which assertion fails with the defect present. Where practical, run the
test against the previous behavior or a temporary controlled mutation and restore it afterward. If the failure
depends on a missing prerequisite or environmental setup, distinguish that from detecting the target regression.
When modifying an existing test, review removed assertions explicitly rather than assuming fewer failures means
better coverage.

Run targeted verification first, then the affected suites and required CI checks. Record commands and outcomes;
do not claim a local browser test passed if browser startup failed. Resolve environment setup when feasible,
otherwise report it as unrun/blocked without weakening the committed test. Performance improvements such as
browser reuse must retain isolation, test intent, and lifecycle coverage.


#### Integration Tests Organization

```
spec/
├── unit/                    # Fast unit tests (future)
├── integration/             # Browser automation tests
│   ├── examples/           # Example-based tests
│   │   └── screenshot_spec.rb
│   └── screenshot_spec.rb  # Feature test suites
├── assets/                 # Test HTML/CSS/JS files
│   ├── grid.html
│   ├── scrollbar.html
│   ├── empty.html
│   └── digits/*.png
├── golden-firefox/         # Reference images
│   └── screenshot-*.png
└── support/               # Test utilities
    ├── test_server.rb
    └── golden_comparator.rb
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
bundle exec rspec spec/integration/screenshot_spec.rb
# Expected: 12 examples, 0 failures (completes in ~8 seconds with optimized spec_helper)
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
# In spec_helper.rb
config.before(:suite) do
  if RSpec.configuration.files_to_run.any? { |f| f.include?('spec/integration') }
    $shared_browser = Puppeteer::Bidi.launch_browser_instance(headless: headless_mode?)
    $shared_test_server = TestServer::Server.new
    $shared_test_server.start
  end
end

def with_test_state(**options)
  if $shared_browser && options.empty?
    # Create new page (tab) per test
    page = $shared_browser.new_page
    context = $shared_browser.default_browser_context

    begin
      yield(page: page, server: $shared_test_server, browser: $shared_browser, context: context)
    ensure
      page.close unless page.closed?  # Clean up tab
    end
  else
    # Fall back to per-test browser for custom options
  end
end
```

**Performance**: ~10 seconds for 35 tests (1 browser launch + 35 tab creations)

##### Performance Results

| Test Suite | Before | After | Improvement |
|------------|--------|-------|-------------|
| **evaluation_spec (23 tests)** | 127s | **7.17s** | **17.7x faster** |
| **screenshot_spec (12 tests)** | 68s | **8.47s** | **8.0x faster** |
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
# In golden_comparator.rb
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

golden = ChunkyPNG::Image.from_file('spec/golden-firefox/screenshot.png')
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

**Solution:** Preserve upstream coordination for shared viewport and lifecycle state. Protocol request IDs do not
serialize those operations. Test deliberate overlapping calls in the supported execution paths; see
[Async coordination](async_programming.md#lifecycle-and-event-ordering). Thread tests alone do not cover Fiber
interleavings within a reactor.

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

# Performance Benchmark

Comparison of Firefox automation libraries performance.

## Results

Tested with Firefox 139.0, 150 iterations of DOM operations.
Time measured from after browser launch to before browser close.

| Library | Protocol | Total Time | Per Iteration |
|---------|----------|------------|---------------|
| Selenium WebDriver | WebDriver | 2.12s | 14.11 ms |
| **puppeteer-bidi** | WebDriver BiDi | 2.85s | 18.97 ms |
| puppeteer-ruby | CDP (Juggler) | 31.02s | 206.81 ms |

## Key Findings

- **puppeteer-bidi is ~11x faster than puppeteer-ruby** for Firefox automation
- Selenium WebDriver is fastest for simple operations, but lacks Puppeteer's high-level API (e.g., `set_content()`, `wait_for_selector()`, request interception)
- puppeteer-bidi provides Puppeteer-compatible API while being significantly faster than puppeteer-ruby
- puppeteer-ruby's CDP-over-Juggler bridge adds significant overhead on Firefox

## Test Operations

Each iteration performs:
- Set HTML content (150 elements)
- Query selectors (`h1`, `li` x20, `.description`)
- Multiple JavaScript evaluations
- DOM property access

## Running Benchmarks

```bash
# Set Firefox path (optional)
export FIREFOX_PATH="/path/to/firefox"

# Run individual benchmarks
ruby benchmark/benchmark_selenium.rb
ruby benchmark/benchmark_puppeteer_bidi.rb
ruby benchmark/benchmark_puppeteer_ruby.rb
```

## Notes

- Selenium uses data URL navigation; Puppeteer variants use `set_content()`
- All tests run in headless mode
- Results may vary based on system configuration

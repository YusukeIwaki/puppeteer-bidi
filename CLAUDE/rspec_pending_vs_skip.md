# RSpec: pending vs skip

## Overview

RSpec provides two mechanisms for handling tests that cannot or should not run: `pending` and `skip`. Understanding when to use each is critical for documenting browser limitations and future work.

## Difference

### skip

**Completely skips the test** - does not run any code:

```ruby
it 'should work' do
  skip 'feature not implemented'

  # This code NEVER runs
  page.do_something
  expect(result).to be_truthy
end
```

**Output**: Test marked as skipped, no execution, no error trace.

### pending

**Runs the test** and expects it to fail:

```ruby
it 'should work' do
  pending 'feature not implemented'

  # This code RUNS and is expected to fail
  page.do_something  # Raises error
  expect(result).to be_truthy
end
```

**Output**: Test marked as pending with full error trace showing exactly what failed.

## When to Use Each

### Use `pending` for:

1. **Browser limitations** - Features not yet supported by Firefox BiDi
2. **Known failures** - Code exists but fails due to external issues
3. **Documentation** - Want to show error trace to document what's missing

### Use `skip` for:

1. **Unimplemented features** - Code doesn't exist yet
2. **Environment issues** - Test requires specific setup not available
3. **Temporary exclusion** - Test is broken and needs fixing

## Firefox BiDi Limitations

For features that exist in BiDi spec but not yet implemented in Firefox, use `pending`:

```ruby
describe 'Page.setJavaScriptEnabled' do
  it 'should work' do
    # Pending: Firefox does not yet support emulation.setScriptingEnabled BiDi command
    pending 'emulation.setScriptingEnabled not supported by Firefox yet'

    with_test_state do |page:, **|
      page.set_javascript_enabled(false)
      expect(page.javascript_enabled?).to be false

      page.goto('data:text/html, <script>var something = "forbidden"</script>')

      error = nil
      begin
        page.evaluate('something')
      rescue => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.message).to include('something is not defined')
    end
  end
end
```

**Why pending, not skip**:
- Code path exists (`page.set_javascript_enabled`)
- BiDi command exists in spec (`emulation.setScriptingEnabled`)
- Firefox just hasn't implemented it yet
- Running the test shows exactly what error Firefox returns

## Output Comparison

### With `skip`

```
Page
  Page.setJavaScriptEnabled
    should work (SKIPPED)
```

No error information, no way to know what's missing.

### With `pending`

```
Page
  Page.setJavaScriptEnabled
    should work (PENDING: emulation.setScriptingEnabled not supported by Firefox yet)

Pending: (Failures listed here are expected and do not affect your suite's status)

  1) Page Page.setJavaScriptEnabled should work
     # emulation.setScriptingEnabled not supported by Firefox yet
     Failure/Error: raise ProtocolError, "BiDi error (#{method}): #{result['error']['message']}"

     Puppeteer::Bidi::Connection::ProtocolError:
       BiDi error (emulation.setScriptingEnabled):
     # ./lib/puppeteer/bidi/connection.rb:71:in 'send_command'
     # ./lib/puppeteer/bidi/core/browsing_context.rb:331:in 'set_javascript_enabled'
     # ./lib/puppeteer/bidi/page.rb:313:in 'set_javascript_enabled'
```

Full error trace shows:
- Which BiDi command failed
- Error message from Firefox
- Complete stack trace
- Where in our code it failed

## Implementation Pattern

### Before (Incorrect - Using skip in before block)

```ruby
describe 'Page.setJavaScriptEnabled' do
  before do
    skip 'emulation.setScriptingEnabled not supported by Firefox yet'
  end

  it 'should work' do
    # Never runs
  end

  it 'setInterval should pause' do
    # Never runs
  end
end
```

**Problems**:
- Tests don't run at all
- No error information
- Not clear which BiDi command is missing

### After (Correct - Using pending in individual tests)

```ruby
describe 'Page.setJavaScriptEnabled' do
  it 'should work' do
    pending 'emulation.setScriptingEnabled not supported by Firefox yet'

    with_test_state do |page:, **|
      # Test code runs and fails with proper error trace
    end
  end

  it 'setInterval should pause' do
    pending 'emulation.setScriptingEnabled not supported by Firefox yet'

    with_test_state do |page:, **|
      # Test code runs and fails with proper error trace
    end
  end
end
```

**Benefits**:
- Tests run and document exact failure
- Each test can have specific pending message
- Easy to identify when Firefox adds support (test will pass)
- Full error trace available for debugging

## Best Practices

### 1. Be Specific in Pending Messages

```ruby
# Good
pending 'emulation.setScriptingEnabled not supported by Firefox yet'

# Bad
pending 'not supported'
```

### 2. Include BiDi Command Name

```ruby
# Good
pending 'browsingContext.setViewport not implemented'

# Bad
pending 'viewport not working'
```

### 3. Document When to Re-check

```ruby
# Good
pending 'network.addIntercept requires Firefox 120+, current: 119'

# Bad
pending 'network interception broken'
```

### 4. Remove Pending When Fixed

When Firefox adds support, the test will fail with:
```
Expected example to fail but it passed
```

This is your signal to remove the `pending` line!

## Firefox BiDi Limitations (Current)

As of this implementation, the following BiDi commands are not supported by Firefox:

1. `emulation.setScriptingEnabled` - Control JavaScript execution
   - Tests: `spec/integration/page_spec.rb` (2 tests)
   - Tests: `spec/integration/click_spec.rb` (1 test)

## Files Changed

- `spec/integration/click_spec.rb`: Changed `skip` to `pending` (line 71)
- `spec/integration/page_spec.rb`: Moved `skip` from before block to individual tests as `pending` (lines 19, 48)

## Test Results

```bash
bundle exec rspec spec/integration/
# 108 examples, 0 failures, 4 pending
```

All pending tests show proper error traces documenting Firefox limitations.

## Key Takeaways

1. **Use `pending` for browser limitations** - Shows what's missing with error trace
2. **Use `skip` for unimplemented features** - Our code doesn't exist yet
3. **Be specific in messages** - Include BiDi command name and reason
4. **Pending in test body, not before block** - Each test should be explicit
5. **Pending tests run code** - They document exact failure mode
6. **Remove pending when fixed** - Test will fail with "expected to fail but passed"

## References

- [RSpec Documentation: Pending and Skipped Examples](https://rspec.info/features/3-12/rspec-core/pending-and-skipped-examples/)
- [WebDriver BiDi Spec](https://w3c.github.io/webdriver-bidi/) - Check which commands are standardized
- [Firefox BiDi Implementation Status](https://wiki.mozilla.org/WebDriver/RemoteProtocol/WebDriver_BiDi) - Check Firefox support

## Commit Reference

See commit: "test: Use pending instead of skip for Firefox unsupported features"

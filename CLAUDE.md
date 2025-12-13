# Puppeteer-BiDi Development Guide

## Project Overview

Port the WebDriver BiDi protocol portions of Puppeteer to Ruby, providing a standards-based tool for Firefox automation.

### Development Principles

- **BiDi-only**: Do not port CDP protocol-related code
- **Standards compliance**: Adhere to W3C WebDriver BiDi specification
- **Firefox optimization**: Maximize BiDi protocol capabilities
- **Ruby conventions**: Design Ruby-idiomatic interfaces

## Quick Reference

### Running Tests

```bash
# All integration tests (requires Firefox Nightly for full functionality)
bundle exec rspec spec/integration/

# Single test file
bundle exec rspec spec/integration/click_spec.rb

# Non-headless mode
HEADLESS=false bundle exec rspec spec/integration/

# Debug protocol messages
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/click_spec.rb

# Use specific Firefox path (e.g., Nightly)
FIREFOX_PATH="/Applications/Firefox Nightly.app/Contents/MacOS/firefox" bundle exec rspec
```

**Note**: Some features (e.g., FileChooser) require Firefox Nightly. The browser launcher prioritizes Nightly automatically.

### Key Architecture

```
Upper Layer (Puppeteer::Bidi)     - User-facing synchronous API
  └── Page, Frame, ElementHandle, JSHandle

Core Layer (Puppeteer::Bidi::Core) - Async operations, returns Async::Task
  └── Session, BrowsingContext, Realm
```

**Critical**: Upper layer methods must call `.wait` on all Core layer method calls. See [Two-Layer Architecture](CLAUDE/two_layer_architecture.md).

### Async Programming

This project uses **Async (Fiber-based)**, NOT concurrent-ruby (Thread-based).

- No Mutex needed (cooperative multitasking)
- Similar to JavaScript async/await
- See [Async Programming Guide](CLAUDE/async_programming.md)

## Development Workflow

1. Study Puppeteer's TypeScript implementation first
2. Understand BiDi protocol calls
3. Implement with proper deserialization
4. Port tests from Puppeteer
5. See [Porting Puppeteer Guide](CLAUDE/porting_puppeteer.md)

## Coding Conventions

### Ruby

- Use Ruby 3.0+ features
- Follow RuboCop guidelines
- Class names: `PascalCase`, Methods: `snake_case`, Constants: `SCREAMING_SNAKE_CASE`

### Type Annotations (rbs-inline)

Use [rbs-inline](https://github.com/soutaro/rbs-inline) for type annotations in Ruby source files.

**Setup:**
- Add `# rbs_inline: enabled` magic comment at the top of the file
- Use Doc style syntax for type annotations

**Example:**
```ruby
# frozen_string_literal: true
# rbs_inline: enabled

class Example
  attr_reader :name #: String

  # @rbs name: String
  # @rbs return: void
  def initialize(name)
    @name = name
  end

  # @rbs selector: String
  # @rbs return: ElementHandle?
  def query_selector(selector)
    # ...
  end
end
```

**Conventions:**
- Use `A?` for nullable types (not `A | nil`)
- Use `A | B | nil` for union types with nil
- Add space around `--` for inline comments: `# @rbs name: String -- the name`
- Public methods should have type annotations

**Generate RBS files:**
```bash
bundle exec rake rbs  # Generates sig/**/*.rbs
```

**Note:** `sig/` directory is gitignored. RBS files are generated automatically during `rake build`.

### Testing

- Use RSpec for unit and integration tests
- Integration tests in `spec/integration/`
- Use `with_test_state` helper for browser reuse

### Test Assets

**CRITICAL**: Always use Puppeteer's official test assets without modification.

- Source: https://github.com/puppeteer/puppeteer/tree/main/test/assets
- Never modify files in `spec/assets/`
- Revert any experimental changes before PRs

## Detailed Documentation

See the [CLAUDE/](CLAUDE/) directory for detailed implementation guides:

### Architecture & Patterns

- **[Two-Layer Architecture](CLAUDE/two_layer_architecture.md)** - Core vs Upper layer, async patterns
- **[Async Programming](CLAUDE/async_programming.md)** - Fiber-based concurrency with socketry/async
- **[Porting Puppeteer](CLAUDE/porting_puppeteer.md)** - Best practices for implementing features
- **[Core Layer Gotchas](CLAUDE/core_layer_gotchas.md)** - EventEmitter/Disposable pitfalls, @disposed conflicts

### Implementation Details

- **[QueryHandler](CLAUDE/query_handler.md)** - CSS, XPath, text selector handling
- **[JavaScript Evaluation](CLAUDE/javascript_evaluation.md)** - `evaluate()` and `evaluate_handle()`
- **[JSHandle and ElementHandle](CLAUDE/jshandle_implementation.md)** - Object handle management
- **[Selector Evaluation](CLAUDE/selector_evaluation.md)** - `eval_on_selector` methods
- **[Click Implementation](CLAUDE/click_implementation.md)** - Mouse input and clicking
- **[Mouse Implementation](CLAUDE/mouse_implementation.md)** - wheel, reset, hover, BoundingBox/Point data classes
- **[Wrapped Element Click](CLAUDE/wrapped_element_click.md)** - getClientRects() for multi-line elements
- **[Navigation Waiting](CLAUDE/navigation_waiting.md)** - waitForNavigation patterns
- **[Frame Architecture](CLAUDE/frame_architecture.md)** - Parent-based frame hierarchy
- **[FileChooser](CLAUDE/file_chooser.md)** - File upload and dialog handling (requires Firefox Nightly)
- **[Error Handling](CLAUDE/error_handling.md)** - Custom exception types

### Testing

- **[Testing Strategy](CLAUDE/testing_strategy.md)** - Test organization and optimization
- **[RSpec pending vs skip](CLAUDE/rspec_pending_vs_skip.md)** - Documenting limitations
- **[Test Server Routes](CLAUDE/test_server_routes.md)** - Dynamic route handling

## Releasing

To release a new version:

1. Update the version number in `lib/puppeteer/bidi/version.rb`
2. Commit the change and push to main
3. Create and push a version tag:
   ```bash
   git tag 1.2.3
   git push origin 1.2.3
   ```

GitHub Actions will automatically build and publish the gem to RubyGems. Supported tag formats:
- `1.2.3` - stable release
- `1.2.3.alpha1` - alpha release
- `1.2.3.beta2` - beta release

**Note:** `RUBYGEMS_API_KEY` must be configured in repository secrets.

## References

- [WebDriver BiDi Specification](https://w3c.github.io/webdriver-bidi/)
- [Puppeteer Documentation](https://pptr.dev/)
- [Puppeteer Source Code](https://github.com/puppeteer/puppeteer)
- [puppeteer-ruby](https://github.com/YusukeIwaki/puppeteer-ruby) - CDP implementation reference

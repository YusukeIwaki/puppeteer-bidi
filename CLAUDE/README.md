# Detailed Implementation Documentation

This directory contains detailed documentation for specific implementation topics in puppeteer-bidi. These documents provide in-depth technical details, debugging techniques, and lessons learned during development.

## Quick Reference

| Document | Topic | Key Takeaway | Lines |
|----------|-------|--------------|-------|
| [javascript_evaluation.md](javascript_evaluation.md) | JS evaluation | IIFE detection is critical | 341 |
| [jshandle_implementation.md](jshandle_implementation.md) | Handle management | resultOwnership must be 'root' | 423 |
| [selector_evaluation.md](selector_evaluation.md) | Selector methods | Use `eval_on_selector` not `$eval` | 198 |
| [error_handling.md](error_handling.md) | Custom exceptions | Type-safe error handling | 232 |
| [click_implementation.md](click_implementation.md) | Click & mouse | session.subscribe is mandatory | 340 |
| [wrapped_element_click.md](wrapped_element_click.md) | Wrapped elements | Use getClientRects() | 280 |
| [testing_strategy.md](testing_strategy.md) | Test optimization | Browser reuse = 19x faster | 236 |
| [frame_architecture.md](frame_architecture.md) | Frame hierarchy | `(parent, browsing_context)` | 150 |
| [rspec_pending_vs_skip.md](rspec_pending_vs_skip.md) | Test documentation | Use `pending` for Firefox | 290 |

**Total**: ~2,490 lines of detailed documentation

## JavaScript and DOM Interaction

### [JavaScript Evaluation](javascript_evaluation.md)

Complete guide to implementing `evaluate()` and `evaluate_handle()` methods.

**Topics covered:**
- Detection logic for expressions, functions, and IIFE
- Argument serialization to BiDi LocalValue format
- Result deserialization from BiDi RemoteValue
- Core::Realm return values and exception handling

**When to read:** When implementing JavaScript execution features or debugging evaluation issues.

**Key concepts:**
- IIFE must be detected and treated as expressions, not functions
- `awaitPromise` and `resultOwnership` are independent parameters
- Always deserialize BiDi results before returning to user

### [JSHandle and ElementHandle](jshandle_implementation.md)

Comprehensive guide to handle management, BiDi protocol parameters, and debugging.

**Topics covered:**
- Critical BiDi parameters: `resultOwnership` and `serializationOptions`
- Handle lifecycle and disposal patterns
- Debugging with `DEBUG_BIDI_COMMAND=1`
- Common pitfalls (arrays must be arrays, dates serialization)
- Comparing with Puppeteer's protocol messages

**When to read:** When implementing handle-based APIs or debugging handle-related issues.

**Key concepts:**
- Set `resultOwnership: 'root'` to get handles
- Handle parameters must be arrays: `[handle_id]` not `handle_id`
- Use Serializer/Deserializer for consistency

### [Selector Evaluation Methods](selector_evaluation.md)

Implementation guide for `eval_on_selector` and `eval_on_selector_all` methods.

**Topics covered:**
- Method naming (Ruby cannot use `$` in names)
- Delegation pattern: Page → Frame → ElementHandle
- Handle lifecycle management with ensure blocks
- Error handling differences between methods
- Performance with large element sets

**When to read:** When implementing selector-based evaluation or optimizing handle usage.

**Key concepts:**
- `eval_on_selector` throws SelectorNotFoundError
- `eval_on_selector_all` returns result for empty arrays
- Always dispose handles in ensure blocks

## Error Handling

### [Error Handling and Custom Exceptions](error_handling.md)

Guide to implementing type-safe error handling with custom exception classes.

**Topics covered:**
- Custom exception hierarchy
- When to use each exception type
- Implementation patterns (assert methods)
- Benefits of type safety vs inline raises
- Testing custom exceptions with regex matching

**When to read:** When adding new error conditions or refactoring error handling.

**Key concepts:**
- Use custom exceptions for type-safe rescue
- Create private assert methods
- Include contextual data in exceptions

## User Input and Interactions

### [Click Implementation](click_implementation.md)

Comprehensive coverage of click functionality and mouse input implementation.

**Topics covered:**
- Architecture: Page → Frame → ElementHandle delegation
- Mouse class and BiDi `input.performActions`
- Critical bug fixes (session.subscribe, event-based URL updates)
- BiDi protocol format requirements
- Test coverage (20 click tests)

**When to read:** When implementing user input features or debugging click issues.

**Key concepts:**
- Must call `session.subscribe` for events to fire
- URL updates happen via events, not direct assignment
- BiDi `origin` must be string `'viewport'`, not hash

### [Wrapped Element Click](wrapped_element_click.md)

Technical deep-dive on clicking wrapped/multi-line text elements.

**Topics covered:**
- Why getBoundingClientRect() fails for wrapped text
- getClientRects() returns multiple boxes
- intersectBoundingBoxesWithFrame viewport clipping algorithm
- Debugging with protocol logs

**When to read:** When debugging click issues with complex layouts or wrapped text.

**Key concepts:**
- Use getClientRects() for wrapped elements
- Click first valid box (width >= 1 && height >= 1)
- Viewport clipping ensures clicks stay visible

## Testing

### [Testing Strategy](testing_strategy.md)

Guide to integration test organization, performance optimization, and debugging.

**Topics covered:**
- Integration test organization and structure
- Performance optimization with browser reuse (19x faster)
- Golden image testing with tolerance
- Debugging techniques (save screenshots, pixel comparison)
- Environment variables (HEADLESS=false)

**When to read:** When adding tests or optimizing test performance.

**Key concepts:**
- Reuse browser across tests for 19x speedup
- Golden image comparison needs pixel tolerance
- Use official Puppeteer test assets

### [RSpec: pending vs skip](rspec_pending_vs_skip.md)

Guide to documenting browser limitations with proper RSpec usage.

**Topics covered:**
- Difference between `pending` (runs and expects failure) and `skip` (doesn't run)
- When to use each for browser limitations
- Output comparison and error trace benefits
- Implementation patterns

**When to read:** When adding tests that depend on Firefox BiDi features.

**Key concepts:**
- Use `pending` for Firefox BiDi limitations
- Use `skip` for unimplemented features
- `pending` provides full error traces

## Architecture

### [Frame Architecture](frame_architecture.md)

Guide to parent-based Frame hierarchy following Puppeteer's design.

**Topics covered:**
- Constructor signature change: `(parent, browsing_context)`
- Recursive page traversal with ternary operator
- Support for nested iframes (future)
- Comparison with Puppeteer's TypeScript implementation

**When to read:** When working on Frame-related features or implementing iframe support.

**Key concepts:**
- First parameter is `parent` (Page or Frame), not `page`
- Use ternary for page traversal: `@parent.is_a?(Page) ? @parent : @parent.page`
- Enables future iframe support

## Organization

These documents are separated from the main CLAUDE.md file to:

1. **Keep CLAUDE.md concise** - Main development guide focuses on high-level concepts
2. **Provide deep dives** - Detailed documents for specific technical topics
3. **Enable easy updates** - Each document can be updated independently
4. **Support onboarding** - New contributors can read specific topics as needed

## Contributing

When adding new detailed documentation:

1. **Create focused documents** - One topic per file
2. **Include code examples** - Show both correct and incorrect approaches
3. **Link to references** - Puppeteer source code, BiDi spec, etc.
4. **Document lessons learned** - What went wrong and how it was fixed
5. **Update this README** - Add new document to appropriate section and quick reference table

## Index by Topic

**Architecture:**
- Frame hierarchy → [frame_architecture.md](frame_architecture.md)
- Parent-child relationships → [frame_architecture.md](frame_architecture.md)

**JavaScript Execution:**
- evaluate() and evaluate_handle() → [javascript_evaluation.md](javascript_evaluation.md)
- IIFE detection → [javascript_evaluation.md](javascript_evaluation.md)
- Argument serialization → [javascript_evaluation.md](javascript_evaluation.md)

**Handle Management:**
- JSHandle and ElementHandle → [jshandle_implementation.md](jshandle_implementation.md)
- resultOwnership parameter → [jshandle_implementation.md](jshandle_implementation.md)
- Handle disposal → [jshandle_implementation.md](jshandle_implementation.md)

**Selector Methods:**
- eval_on_selector → [selector_evaluation.md](selector_evaluation.md)
- eval_on_selector_all → [selector_evaluation.md](selector_evaluation.md)
- Delegation patterns → [selector_evaluation.md](selector_evaluation.md)

**Error Handling:**
- Custom exceptions → [error_handling.md](error_handling.md)
- Type-safe rescue → [error_handling.md](error_handling.md)
- Assert methods → [error_handling.md](error_handling.md)

**Click Implementation:**
- Mouse input → [click_implementation.md](click_implementation.md)
- session.subscribe → [click_implementation.md](click_implementation.md)
- Event-based URL updates → [click_implementation.md](click_implementation.md)

**Wrapped Elements:**
- getClientRects() → [wrapped_element_click.md](wrapped_element_click.md)
- Viewport clipping → [wrapped_element_click.md](wrapped_element_click.md)
- intersectBoundingBoxesWithFrame → [wrapped_element_click.md](wrapped_element_click.md)

**Testing:**
- Integration tests → [testing_strategy.md](testing_strategy.md)
- Browser reuse optimization → [testing_strategy.md](testing_strategy.md)
- Golden image testing → [testing_strategy.md](testing_strategy.md)
- pending vs skip → [rspec_pending_vs_skip.md](rspec_pending_vs_skip.md)

## Related Documentation

- **Main guide**: [CLAUDE.md](../CLAUDE.md) - High-level development guide (833 lines)
- **Core layer**: [lib/puppeteer/bidi/core/README.md](../lib/puppeteer/bidi/core/README.md) - Core BiDi abstraction layer
- **API reference**: RBS type definitions (future)

## Statistics

- **Total detailed docs**: 9 files
- **Total lines**: ~2,490 lines
- **Main CLAUDE.md**: 833 lines (reduced from 2,315)
- **Reduction**: 64% of detailed content moved to focused documents

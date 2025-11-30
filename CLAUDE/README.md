# Detailed Implementation Documentation

This directory contains detailed documentation for specific implementation topics in puppeteer-bidi.

## Quick Reference

| Document | Topic | Key Takeaway |
|----------|-------|--------------|
| [async_programming.md](async_programming.md) | Fiber-based async | Use Async, NOT concurrent-ruby |
| [two_layer_architecture.md](two_layer_architecture.md) | Core vs Upper layer | Always call `.wait` on Core methods |
| [porting_puppeteer.md](porting_puppeteer.md) | Implementing features | Study TypeScript first, port tests |
| [query_handler.md](query_handler.md) | Selector handling | Override script methods, use PuppeteerUtil |
| [javascript_evaluation.md](javascript_evaluation.md) | JS evaluation | IIFE detection is critical |
| [jshandle_implementation.md](jshandle_implementation.md) | Handle management | resultOwnership must be 'root' |
| [selector_evaluation.md](selector_evaluation.md) | Selector methods | Use `eval_on_selector` not `$eval` |
| [error_handling.md](error_handling.md) | Custom exceptions | Type-safe error handling |
| [click_implementation.md](click_implementation.md) | Click & mouse | session.subscribe is mandatory |
| [wrapped_element_click.md](wrapped_element_click.md) | Wrapped elements | Use getClientRects() |
| [navigation_waiting.md](navigation_waiting.md) | waitForNavigation | Event-driven with Async::Promise |
| [testing_strategy.md](testing_strategy.md) | Test optimization | Browser reuse = 19x faster |
| [frame_architecture.md](frame_architecture.md) | Frame hierarchy | `(parent, browsing_context)` |
| [rspec_pending_vs_skip.md](rspec_pending_vs_skip.md) | Test documentation | Use `pending` for Firefox |
| [test_server_routes.md](test_server_routes.md) | Dynamic routes | `server.set_route` for tests |

## Architecture & Patterns

### [Async Programming](async_programming.md)

Guide to Fiber-based async programming with socketry/async.

**Key concepts:**
- Use Async (Fiber-based), NOT concurrent-ruby (Thread-based)
- No Mutex needed - cooperative multitasking
- WebSocket messages must use `Async do` for non-blocking processing

### [Two-Layer Architecture](two_layer_architecture.md)

Core vs Upper layer separation for async complexity management.

**Key concepts:**
- Core layer returns `Async::Task`
- Upper layer calls `.wait` on all Core methods
- User-facing API is synchronous

### [Porting Puppeteer](porting_puppeteer.md)

Best practices for implementing Puppeteer features in Ruby.

**Key concepts:**
- Study TypeScript implementation first
- Port corresponding test cases
- Use official test assets without modification

## Implementation Details

### [QueryHandler](query_handler.md)

Extensible selector handling for CSS, XPath, text selectors.

**Key concepts:**
- Override `query_one_script` and `query_all_script`
- TextQueryHandler uses PuppeteerUtil directly (closure dependency)
- Handle adoption pattern for navigation

### [JavaScript Evaluation](javascript_evaluation.md)

Implementation of `evaluate()` and `evaluate_handle()`.

**Key concepts:**
- IIFE must be detected and treated as expressions
- Always deserialize BiDi results before returning

### [JSHandle and ElementHandle](jshandle_implementation.md)

Handle management and BiDi protocol parameters.

**Key concepts:**
- Set `resultOwnership: 'root'` to get handles
- Handle parameters must be arrays

### [Selector Evaluation](selector_evaluation.md)

Implementation of `eval_on_selector` methods.

**Key concepts:**
- Delegation pattern: Page → Frame → ElementHandle
- Always dispose handles in ensure blocks

### [Click Implementation](click_implementation.md)

Mouse input and click functionality.

**Key concepts:**
- Must call `session.subscribe` for events
- URL updates happen via events

### [Wrapped Element Click](wrapped_element_click.md)

Clicking wrapped/multi-line text elements.

**Key concepts:**
- Use getClientRects() for wrapped elements
- Viewport clipping ensures clicks stay visible

### [Navigation Waiting](navigation_waiting.md)

waitForNavigation patterns.

**Key concepts:**
- Event-driven with Async::Promise
- Attach to existing navigations before block execution

### [Frame Architecture](frame_architecture.md)

Parent-based frame hierarchy.

**Key concepts:**
- First parameter is `parent` (Page or Frame)
- Enables future iframe support

### [Error Handling](error_handling.md)

Custom exception types.

**Key concepts:**
- Use custom exceptions for type-safe rescue
- Include contextual data in exceptions

## Testing

### [Testing Strategy](testing_strategy.md)

Test organization and optimization.

**Key concepts:**
- Reuse browser across tests for 19x speedup
- Use official Puppeteer test assets

### [RSpec: pending vs skip](rspec_pending_vs_skip.md)

Documenting browser limitations.

**Key concepts:**
- Use `pending` for Firefox BiDi limitations
- Use `skip` for unimplemented features

### [Test Server Routes](test_server_routes.md)

Dynamic route handling for tests.

**Key concepts:**
- `server.set_route(path)` for intercepting requests
- `server.wait_for_request(path)` for synchronization

## Related Documentation

- **Main guide**: [CLAUDE.md](../CLAUDE.md) - High-level development guide
- **Core layer**: [lib/puppeteer/bidi/core/README.md](../lib/puppeteer/bidi/core/README.md) - Core BiDi abstraction layer

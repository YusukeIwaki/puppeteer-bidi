# Detailed Implementation Documentation

This directory contains detailed documentation for specific implementation topics in puppeteer-bidi. These documents provide in-depth technical details, debugging techniques, and lessons learned during development.

## Architecture and Design

### [Frame Architecture](frame_architecture.md)

Documents the parent-based Frame hierarchy implementation following Puppeteer's design.

**Topics covered:**
- Constructor signature change: `(parent, browsing_context)` instead of `(browsing_context, page)`
- Recursive page traversal using ternary operator
- Support for nested iframes (future)
- Comparison with Puppeteer's TypeScript implementation

**When to read:** When working on Frame-related features or implementing iframe support.

## Click and Mouse Input

### [Wrapped Element Click](wrapped_element_click.md)

Explains why wrapped text elements require special handling and how getClientRects() solves the problem.

**Topics covered:**
- getClientRects() vs getBoundingClientRect() for multi-line elements
- Why clicking the center of bounding box fails for wrapped text
- intersectBoundingBoxesWithFrame viewport clipping algorithm
- Complete implementation with code examples

**When to read:** When debugging click issues, implementing element interactions, or working with complex layouts.

## Testing Best Practices

### [RSpec: pending vs skip](rspec_pending_vs_skip.md)

Clarifies when to use `pending` vs `skip` in RSpec tests, especially for documenting browser limitations.

**Topics covered:**
- Difference between `pending` (runs and expects failure) and `skip` (doesn't run)
- When to use each: browser limitations vs unimplemented features
- How to document Firefox BiDi limitations with proper error traces
- Output comparison and benefits of each approach

**When to read:** When adding new tests that depend on Firefox BiDi features or documenting known limitations.

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
5. **Update this README** - Add new document to appropriate section

## Quick Reference

| Document | Key Takeaway | Lines |
|----------|--------------|-------|
| frame_architecture.md | Use `(parent, browsing_context)` constructor | 150 |
| wrapped_element_click.md | Use getClientRects() for wrapped elements | 280 |
| rspec_pending_vs_skip.md | Use `pending` for browser limitations | 290 |

## Related Documentation

- **Main guide**: [CLAUDE.md](../CLAUDE.md) - High-level development guide
- **Core layer**: [lib/puppeteer/bidi/core/README.md](../lib/puppeteer/bidi/core/README.md) - Core BiDi abstraction layer
- **API reference**: RBS type definitions (future)

## Index

Use this index to quickly find implementation details:

**Architecture:**
- Frame hierarchy → frame_architecture.md
- Parent-child relationships → frame_architecture.md

**Click Implementation:**
- Wrapped elements → wrapped_element_click.md
- Viewport clipping → wrapped_element_click.md
- getClientRects() → wrapped_element_click.md

**Testing:**
- pending vs skip → rspec_pending_vs_skip.md
- Firefox limitations → rspec_pending_vs_skip.md
- Error trace documentation → rspec_pending_vs_skip.md

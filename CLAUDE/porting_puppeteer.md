# Porting Puppeteer to Ruby

Best practices for implementing Puppeteer features in puppeteer-bidi.

## Scope, evidence, and completion

Local documentation is guidance, not an exhaustive list of upstream requirements. Absence from `AGENTS.md`, a
topic guide, or a skill does not make behavior optional. A missing Ruby prerequisite is implementation work,
not evidence that an in-scope feature can be stubbed or its test skipped.

Before implementing or reviewing a port:

1. Record the source and target upstream tags/SHAs, the Ruby base/head, and the issue's requested scope. Follow
   fixed comparison endpoints when supplied. If the issue changes during the work, report the difference instead
   of silently changing targets or claiming to cover the updated issue.
2. Read the actual upstream diff, implementation, tests, and expectations at those refs. Include shared API/base
   classes, decorators, utilities, injected code, and dependencies, not just files under `src/bidi/`.
3. Maintain a concise mapping in the PR description or a linked review note:

   | Upstream behavior/test (pinned source link) | Ruby implementation/spec | Adaptation or applicability reason | Verification result |
   | --- | --- | --- | --- |
   | One row per behavior or test scenario | Include required call paths | Explain any contract difference | Passed, failed, pending, skipped, or unrun, with evidence |

   Group cases only when their individual assertions and applicability remain traceable. Cover all in-scope
   cases, including upstream tests that are disabled on particular platforms. CDP-only behavior remains out of
   scope; browser-independent behavior is not excluded merely because CDP also implements it.
4. Port the prerequisites and tests needed to exercise the behavior through the public API. Do not replace missing
   behavior with a constant result, no-op, fallback, or mocked implementation to produce a passing check.
5. Before claiming completion, reconcile the mapping with the final diff and test output. Report exact commands,
   relevant Ruby/browser/dependency versions, failures, exclusions, and unrun checks. A startup failure is not a
   passing integration run; a skipped or pending example is not implemented coverage. Inspect required CI results
   and distinguish pending CI from successful CI. Do not use an issue-closing claim when in-scope work remains.

For adversarial review, try to falsify parity: identify a concrete input, call path, event order, or dependency
behavior that would distinguish the port from upstream. Reproduce suspected defects where possible, and clearly
separate reproduced failures from source-based concerns and environmental blockers. State when substantial
re-porting is warranted instead of minimizing gaps because the existing tests pass.

## 1. Reference Implementation First

**Always consult the official Puppeteer implementation before implementing features:**

- **TypeScript source files**:
  - `packages/puppeteer-core/src/bidi/Page.ts` - High-level Page API
  - `packages/puppeteer-core/src/bidi/core/BrowsingContext.ts` - Core BiDi context
  - `packages/puppeteer-core/src/api/Page.ts` - Common Page interface

- **Test files**:
  - Discover browser tests under `test/src/` and colocated unit tests under `packages/` at the chosen ref;
    filenames may use `.test.ts` or `.spec.ts`
  - Read `test/TestExpectations.json` (or its equivalent at that ref) for browser/protocol/platform conditions
  - `test/golden-firefox/` - Golden images for visual regression testing

**Example workflow:**

```ruby
# 1. Pin upstream refs and map implementation, prerequisites, and tests
# 2. Trace the public API to the protocol/dependency behavior
# 3. Implement equivalent observable behavior with minimal Ruby adaptation
# 4. Preserve test bodies and assertions, then exercise the real call path
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

### Audit the complete contract

Follow the public entry point through wrappers, factories, inherited helpers, core, transport, and injected code.
Check every relevant construction path, including calls inside an Async reactor and through `ReactorRunner`.
An option accepted by a signature is not implemented if a wrapper drops it. A generated helper is not reachable
unless Ruby parsing, dispatch, and required query handlers actually call it.

For each changed behavior, check the relevant contracts:

- **Inputs:** omission versus explicit `nil`, `false`, zero, defaults, validation, and conditional payload keys.
  Use key presence when upstream uses `'key' in options`; do not serialize validation defaults as supplied values.
- **Outputs and errors:** return values, error classes/messages, propagation, disabled behavior, and side effects.
  Trace logger/options through objects created later; verify enabled output, disabled silence, and no duplication.
- **Collections and streams:** identity/deduplication, iteration or reading, piping, completion, close events, and
  disposal. Replacing a `Set` with an `Array` or dropping a TypeScript interface can change observable behavior.
- **Lifecycle:** upstream guards, idempotence, concurrent callers, cancellation, retries, and cleanup on failure.
  Preserve when callers complete, not just when a flag is set. See [Async coordination](async_programming.md).
- **I/O:** buffering and flush, read and write paths, symlinks, file modes, and error handling. Check all operations
  governed by a shared policy, not only the operation that first exposed the issue.

Read the installed dependency's implementation or versioned documentation when translating Node.js behavior to
Ruby. Similar method names and options do not establish equivalence: determine whether writes are buffered,
whether removal suppresses errors, which errors are retried, and the retry count/backoff. Supplement mocks with
tests against the real dependency boundary. Do not mock a method to raise an error it actually suppresses and
then treat the retry path as verified. A necessary adapter (such as an explicit flush) is appropriate; speculative
fallbacks, extra protocol calls, or swallowed errors require a demonstrated contract need and regression coverage.

Ruby naming and return-type adaptations are expected, but explain semantic differences in the mapping. Preserve
upstream control flow where feasible; do not redesign behavior merely because the source construct has no direct
Ruby syntax equivalent.

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

Trace upstream `Frame.setContent` and its shared `setFrameContent` helper. Preserve document writing and lifecycle
waiting. Replacing `document.open/write/close` with navigation to a data URL changes the document URL and navigation
behavior; matching the rendered HTML alone does not establish parity. Consult the chosen upstream ref and the
existing Ruby `Frame#set_content` implementation before changing this path.

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

- **Source**: `test/assets/` at the exact upstream revision used for the port, not a moving `main`
- **Rule**: Copy relevant official fixtures unchanged into `spec/assets/`; do not simplify their contents
- **Verification**: Compare the fixtures used or changed by the port against that ref and revert experimental edits

**Why this matters**: Test assets are designed to test specific edge cases (rotated elements, complex layouts, etc.). Using simplified versions defeats the purpose of these tests.

## 9. API Coverage Update

`API_COVERAGE.md` is generated. Do not hand-edit rows, version metadata, checkmarks, or counts.

1. Read `development/puppeteer_revision.txt` and the API Coverage job in `.github/workflows/check.yml`.
2. Use an upstream checkout at that exact revision, including API docs and package metadata. When advancing the
   repository's supported upstream baseline, update the pin and generated output together. For a selective
   backport, state its target separately; do not imply the entire newer release is supported by advancing a label.
3. From the repository root, run the same generator as CI (use `rbenv exec` if needed):

```bash
bundle exec ruby development/generate_api_coverage.rb \
  --puppeteer-dir development/puppeteer \
  --cache-dir development/cache \
  --output API_COVERAGE.md
```

4. Verify that the checkout SHA, generated version/commit, and cache provenance agree. The generator validates
   the cache against the checkout commit. Regeneration must reproduce the proposed artifact without manual fixes;
   if discovery/mapping is wrong, correct the generator with appropriate verification instead of patching output.

For injected-source updates, pass the intended package version explicitly to `scripts/update_injected_source.rb`.
Review the downloaded artifact and version provenance, then run behavior tests through Ruby. Matching generated
bytes, finding a marker string, or obtaining a coverage checkmark proves neither reachability nor correctness.

See [test fidelity](testing_strategy.md#upstream-test-fidelity) and the
[pending/skip policy](rspec_pending_vs_skip.md) before interpreting test totals as completion evidence.

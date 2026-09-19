# Repository Guidelines

## Start Here (Project-Specific Guidance)

- Read `CLAUDE.md` and `CLAUDE/` first; they define the core async architecture, porting workflow, and testing strategy.
- Ruby: requires `>= 3.2` (CI covers 3.2–3.4). Prefer a version manager (`rbenv`, `asdf`, etc.) over system Ruby.

## Project Structure & Module Organization

- `lib/puppeteer/bidi/`: user-facing API (sync, calls `.wait`).
- `lib/puppeteer/bidi/core/`: low-level BiDi core (async, returns `Async::Task`).
- `spec/integration/`: browser-driven specs; fixtures in `spec/assets/`.

## Build, Test, and Development Commands

- See `DEVELOPMENT.md` for the full command list and environment variables.
- Run RSpec via `rbenv exec bundle exec rspec ...` when using rbenv.

## Coding Style & Naming Conventions

- Ruby: 2-space indent, double-quoted strings, ~120 char lines; follow RuboCop (`.rubocop.yml`).
- BiDi-only: do not introduce CDP-related ports.
- Async: core returns `Async::Task`; upper layer must call `.wait` on every core call (see `CLAUDE/two_layer_architecture.md`).
- Reviews to watch: WS messages can be handled out-of-order; “wait for event” code must not hang (register listeners before commands, handle “already happened”, cancel on errors).

## Testing Guidelines

- Prefer `spec/integration/` and the shared-browser `with_test_state` pattern (see `CLAUDE/testing_strategy.md`).
- Preserve upstream test bodies, assertions, event ordering, and negative/timing checks. A passing substitute test is not evidence that the original behavior works.
- Missing documentation, missing Ruby prerequisites, or a failing test do not justify stubbing behavior or adding `skip`/`pending`. Implement in-scope behavior; document genuine exclusions using [the pending/skip policy](CLAUDE/rspec_pending_vs_skip.md).

## Commit & Pull Request Guidelines

- See `DEVELOPMENT.md` for commit, PR, and release conventions.

## Agent Notes (Porting/Review)

- Follow [the porting workflow](CLAUDE/porting_puppeteer.md): pin the upstream range and map each in-scope behavior and test to Ruby implementation and verification evidence. Local guides are not an exhaustive feature specification.
- Trace the public API through wrappers, factories, inherited helpers, core, transport, and injected code. Port required prerequisites; generated-source updates or method presence alone do not establish parity.
- Preserve upstream contracts with the smallest necessary Ruby adaptation. Verify actual dependency semantics, including buffering/flush, error propagation, cleanup, and collection/lifecycle behavior; mocks must not invent a dependency contract.
- Fibers can interleave at waits and I/O. Preserve upstream guards and completion semantics with Async-compatible coordination; test concurrent callers and event/error ordering.
- When porting from upstream TS, mirror optional vs default fields: defaults are for validation, and optional keys should be omitted from payloads unless explicitly provided.
- Match upstream error messages as closely as possible (including interpolated values) so tests align with Puppeteer.
- In core layer option checks, use key presence (`options.key?`) when upstream uses `'in'` to distinguish "missing" from `nil`.
- Compare implementation, shared API/utilities, colocated unit tests, browser tests, and platform/protocol expectations at the chosen upstream ref. Discover current test paths instead of assuming a `.spec.ts` or `.test.ts` suffix.
- Regenerate `API_COVERAGE.md` with the pinned revision and repository generator; never hand-edit coverage counts or treat them as behavior verification. Report passed, failed, pending, skipped, and unrun checks separately, and do not claim an issue is fixed while in-scope gaps remain.

## Security & Configuration Tips

- Do not commit credentials; review network-fetched changes (e.g., `scripts/update_injected_source.rb` → `lib/puppeteer/bidi/injected.js`) carefully.

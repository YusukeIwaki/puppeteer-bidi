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
- Use `pending` for browser limitations vs `skip` for unimplemented features.

## Commit & Pull Request Guidelines

- See `DEVELOPMENT.md` for commit, PR, and release conventions.

## Agent Notes (Porting/Review)

- When porting from upstream TS, mirror optional vs default fields: defaults are for validation, and optional keys should be omitted from payloads unless explicitly provided.
- Match upstream error messages as closely as possible (including interpolated values) so tests align with Puppeteer.
- In core layer option checks, use key presence (`options.key?`) when upstream uses `'in'` to distinguish "missing" from `nil`.
- During reviews, compare both implementation (`packages/puppeteer-core/src/bidi/*.ts`) and tests (`test/src/page.spec.ts`) to catch behavior parity gaps.

## Security & Configuration Tips

- Do not commit credentials; review network-fetched changes (e.g., `scripts/update_injected_source.rb` → `lib/puppeteer/bidi/injected.js`) carefully.

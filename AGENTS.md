# Repository Guidelines

## Start Here (Project-Specific Guidance)

- Read `CLAUDE.md` and `CLAUDE/` first; they define the core async architecture, porting workflow, and testing strategy.
- Ruby: requires `>= 3.2` (CI covers 3.2–3.4). Prefer a version manager (`rbenv`, `asdf`, etc.) over system Ruby.

## Project Structure & Module Organization

- `lib/puppeteer/bidi/`: user-facing API.
- `lib/puppeteer/bidi/core/`: low-level BiDi core (see `lib/puppeteer/bidi/core/README.md`).
- `spec/integration/`: browser-driven specs; fixtures in `spec/assets/`.
- `sig/`: generated RBS (`sig/_external.rbs`, `sig/_supplementary.rbs` are manual).

## Build, Test, and Development Commands

- `bundle install`: install dependencies.
- `bundle exec rake`: run `spec` + `rubocop` (default task).
- `bundle exec rspec [path]`: run tests (e.g., `bundle exec rspec spec/integration/click_spec.rb`).
- `bundle exec rake rbs && bundle exec steep check`: generate RBS and type-check.

Useful env vars:
- `HEADLESS=false`, `FIREFOX_PATH=/path/to/firefox`, `DEBUG_BIDI_COMMAND=1`.

## Coding Style & Naming Conventions

- Ruby: 2-space indent, double-quoted strings, ~120 char lines; follow RuboCop (`.rubocop.yml`).
- BiDi-only: do not introduce CDP-related ports.
- Async: core returns `Async::Task`; upper layer must call `.wait` on every core call (see `CLAUDE/two_layer_architecture.md`).
- Reviews to watch: WS messages can be handled out-of-order; “wait for event” code must not hang (register listeners before commands, handle “already happened”, cancel on errors).

## Testing Guidelines

- Framework: RSpec; prefer `spec/integration/` for browser-visible behavior.
- Use the shared-browser `with_test_state` pattern (see `CLAUDE/testing_strategy.md`).
- Keep `spec/assets/` in sync with upstream Puppeteer assets; use `pending` (browser limitation) vs `skip` (not implemented).

## Commit & Pull Request Guidelines

- Commit subjects are typically short and imperative; many follow Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, `test:`). Release commits/tags use `X.Y.Z` and `X.Y.Z.betaN`.
- PRs should include: clear description, rationale, and tests. Run `bundle exec rake` and (when relevant) `rake rbs && steep check`.
- If you change user-facing behavior/APIs, update `README.md` and relevant docs under `CLAUDE/`, plus any rbs-inline annotations.

## Security & Configuration Tips

- Do not commit credentials; review network-fetched changes (e.g., `scripts/update_injected_source.rb` → `lib/puppeteer/bidi/injected.js`) carefully.

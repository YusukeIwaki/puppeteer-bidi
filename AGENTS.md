# Agent / Code Review Notes

This repo is a Ruby port of Puppeteer’s BiDi implementation. For full guidance, start with `CLAUDE.md` and the `CLAUDE/` docs.

## Quick review checklist (things that easily bite)

- **Ruby version**: The repo targets the version in `.ruby-version` (currently `3.4.1`). On macOS you may accidentally run system Ruby (e.g. `2.6`). Prefer `rbenv exec ...` when running `ruby`, `bundle`, `rspec`, etc.
- **Two-layer architecture**: Core layer returns `Async::Task`; upper-layer APIs should `.wait` on core calls. In review, watch for missing `.wait` that changes sync/async behavior.
- **BiDi message ordering**: `lib/puppeteer/bidi/transport.rb` processes each incoming WS message in its own `Async do`. This avoids deadlocks, but means **command responses and events can be handled out-of-order** vs Node’s typical event-loop behavior. If code depends on state set by events (e.g. `page.closed?`, `browser.pages` removal), it may need explicit event-based waiting.
- **Event-based waits must not hang**: When adding “wait for event” logic (e.g. waiting for `:closed` after `browsingContext.close`), review all branches:
  - register the listener **before** sending the command
  - consider “already closed” / “event happened early”
  - ensure error/early-return branches resolve/cancel the wait to avoid indefinite blocking
  - special case: `browsingContext.close` for **non-top-level contexts (iframes)** can fail with `"... is not top-level"`; children are auto-closed when the parent closes, so don’t wait forever for a close you didn’t initiate.
- **Test assets policy**: Files under `spec/assets/` must be exact copies from Puppeteer upstream (`puppeteer/test/assets`). If new assets are added, verify with `curl` + `diff` and avoid “simplified” local variants.
- **RSpec `pending` vs `skip`**: Use `pending` for browser/Firefox BiDi limitations where the code path exists (so the failure documents the real error), and `skip` when a feature isn’t implemented at all. In review, ensure pending tests fail for the intended reason (not unrelated argument/signature errors).


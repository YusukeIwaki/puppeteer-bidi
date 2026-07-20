# Codex upstream release review

`review-upstream-puppeteer.yml` checks the latest stable Puppeteer release every Saturday. It runs Codex only when
`development/puppeteer_revision.txt` refers to a different Puppeteer version, then opens one issue for that exact
revision-to-release range.

## Required repository secret

- `CODEX_ENC_APP_ID`: GitHub App ID for the installation that can access `YusukeIwaki/codex.enc`.
- `CODEX_ENC_APP_PRIVATE_KEY`: private key for that GitHub App.
- `CODEX_ENC_PASSPHRASE`: passphrase used to encrypt and decrypt `codex.enc`.

The GitHub App installation must grant repository contents read/write access to the private
`YusukeIwaki/codex.enc` repository. The workflow requests a repository-scoped installation token for clone and a
fresh write token only when refreshed credentials need to be pushed. The clone token is explicitly revoked as soon
as the encrypted repository has been fetched.

## Runtime controls

- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh` (Extra High)
- Codex CLI: `0.144.6`
- Permission profile: workspace writes with command network access limited to GitHub hosts and `pptr.dev`
- Schedule: every Saturday at 03:17 Asia/Tokyo
- Manual run: **Actions → Review upstream Puppeteer releases → Run workflow**

The workflow clones the encrypted auth repository into the runner's temporary directory, decrypts `codex.enc` to a
temporary `auth.json`, and records its SHA-256 before running Codex. If Codex refreshes the file, the workflow
re-encrypts it, commits only `codex.enc`, rebases on `main`, and pushes it with a fresh GitHub App token. Plaintext
credentials and the temporary clone are removed before the job finishes.

Codex receives public network access for upstream research, but the GitHub App tokens and encryption passphrase are
not present in its environment. Its permission profile also denies model-invoked shell commands access to the exact
runtime `auth.json` path, the cloned auth repository, and the pre-run credential hash. A separate job validates the
schema-constrained JSON and uses the job-scoped `GITHUB_TOKEN` with only `issues: write` for deterministic issue
creation, updates, and comments.
The issue body includes a hidden range marker. Before creating an issue, the workflow looks for an open issue with
the exact marker, another marker from this workflow, or a title matching the repository's existing
`Track upstream Puppeteer ... BiDi/Firefox changes` convention. It updates the most relevant open issue instead of
creating a duplicate. Whenever it creates or updates an issue, it posts a comment such as
`puppeteer-bidi should be ported from upstream v25.3.1`, using the detected latest stable version. A hidden content
hash makes the notification idempotent across retries while still allowing a new comment when the generated report
changes. If the title, body, and matching notification are already current, it performs no write.

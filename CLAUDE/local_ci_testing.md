# Local CI Testing

Guide for reproducing Linux CI failures locally on macOS.

## Prerequisites

- Docker Desktop for Mac installed and running
- Apple Silicon Mac requires Rosetta (for x86_64 emulation)

## Using Dockerfile.ci-test

The repository includes `Dockerfile.ci-test` which mirrors the GitHub Actions Ruby 4.0 CI environment:

- Base image: `ruby:4.0-slim-bookworm`
- Firefox Nightly installed via Mozilla APT repository
- All necessary build dependencies

### Build the Docker Image

```bash
# On Apple Silicon Mac, specify platform for x86_64 emulation
docker build --platform linux/amd64 -t puppeteer-bidi-ci-test -f Dockerfile.ci-test .
```

### Run Tests

```bash
# Run all integration tests
docker run --rm --platform linux/amd64 puppeteer-bidi-ci-test \
  bundle exec rspec spec/integration/

# Run a specific test file
docker run --rm --platform linux/amd64 puppeteer-bidi-ci-test \
  bundle exec rspec spec/integration/click_spec.rb

# Run unit tests only
docker run --rm --platform linux/amd64 puppeteer-bidi-ci-test \
  bundle exec rspec --exclude-pattern "spec/integration/**/*_spec.rb"

# Run with headful mode (xvfb)
docker run --rm --platform linux/amd64 puppeteer-bidi-ci-test \
  xvfb-run --server-args="-screen 0 1024x768x24" \
  bundle exec rspec spec/integration/
```

### Interactive Debugging

```bash
# Start a shell in the container
docker run --rm -it --platform linux/amd64 puppeteer-bidi-ci-test bash

# Inside container:
bundle exec rspec spec/integration/some_spec.rb
```

### Environment Variables

The Dockerfile sets these defaults:
- `HEADLESS=true`
- `FIREFOX_PATH=/usr/bin/firefox-nightly`

Override as needed:
```bash
docker run --rm --platform linux/amd64 \
  -e HEADLESS=false \
  -e DEBUG_BIDI_COMMAND=1 \
  puppeteer-bidi-ci-test \
  xvfb-run bundle exec rspec spec/integration/click_spec.rb
```

## Rebuilding After Changes

When you modify `Gemfile` or source files, rebuild the image:

```bash
docker build --platform linux/amd64 -t puppeteer-bidi-ci-test -f Dockerfile.ci-test .
```

## Notes

- Firefox Nightly is x86_64 only, so `--platform linux/amd64` is required on Apple Silicon
- The first build takes longer due to Rosetta emulation
- Tests may run slower than on native Linux due to emulation overhead

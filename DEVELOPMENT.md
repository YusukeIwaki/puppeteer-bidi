# Development guide

## Running checks

```bash
# Run all specs and RuboCop
bundle exec rake

# Run non-browser RSpec tests
bundle exec rspec

# Run browser integration tests (launches Firefox)
bundle exec smartest

# Type checking
bundle exec rake rbs && bundle exec steep check
```

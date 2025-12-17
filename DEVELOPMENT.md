# Development guide

## Running checks

```bash
# Run all specs and RuboCop
bundle exec rake

# Only run integration specs (launches Firefox)
bundle exec rspec spec/integration/

# Type checking
bundle exec rake rbs && bundle exec steep check
```

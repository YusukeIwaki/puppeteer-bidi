# Puppeteer::BiDi

A Ruby port of [Puppeteer](https://pptr.dev/) using the WebDriver BiDi protocol for Firefox automation.

## Overview

`puppeteer-bidi` is a Ruby implementation of Puppeteer that leverages the [WebDriver BiDi protocol](https://w3c.github.io/webdriver-bidi/) to automate Firefox browsers. Unlike the existing [puppeteer-ruby](https://github.com/YusukeIwaki/puppeteer-ruby) gem which uses the Chrome DevTools Protocol (CDP), this gem focuses specifically on BiDi protocol support for cross-browser automation.

### Why BiDi?

- **Cross-browser compatibility**: BiDi is a W3C standard protocol designed to work across different browsers
- **Firefox-first**: While CDP is Chrome-centric, BiDi provides better support for Firefox automation
- **Future-proof**: BiDi represents the future direction of browser automation standards

### Relationship with puppeteer-ruby

This gem complements the existing `puppeteer-ruby` ecosystem:

- **puppeteer-ruby**: Uses CDP (Chrome DevTools Protocol) → Best for Chrome/Chromium automation
- **puppeteer-bidi** (this gem): Uses BiDi protocol → Best for Firefox automation

This gem ports only the BiDi-related portions of Puppeteer to Ruby, intentionally excluding CDP implementations.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add puppeteer-bidi
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install puppeteer-bidi
```

Or add this line to your application's Gemfile:

```ruby
gem 'puppeteer-bidi'
```

## Prerequisites

- Ruby 3.0 or higher
- Firefox browser with BiDi support

## Usage

```ruby
require 'puppeteer/bidi'

# Launch Firefox with BiDi protocol
browser = Puppeteer::Bidi.launch(browser: :firefox)

# Navigate to a page
page = browser.new_page
page.goto('https://example.com')

# Interact with the page
page.screenshot(path: 'screenshot.png')

# Close the browser
browser.close
```

### Basic Examples

#### Taking Screenshots

```ruby
require 'puppeteer/bidi'

browser = Puppeteer::Bidi.launch(browser: :firefox)
page = browser.new_page
page.goto('https://github.com')
page.screenshot(path: 'github.png')
browser.close
```

#### Executing JavaScript

```ruby
require 'puppeteer/bidi'

browser = Puppeteer::Bidi.launch(browser: :firefox)
page = browser.new_page
page.goto('https://example.com')

title = page.evaluate('() => document.title')
puts "Page title: #{title}"

browser.close
```

## Project Status

This project is in early development. The API may change as the implementation progresses.

### Planned Features

- Browser launching and connection
- Page navigation and lifecycle management
- JavaScript evaluation
- DOM manipulation
- Event handling
- Network interception
- Screenshots and PDF generation

## Comparison with Puppeteer (Node.js)

This gem aims to provide a Ruby-friendly API that closely mirrors the original Puppeteer API while following Ruby conventions and idioms.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YusukeIwaki/puppeteer-bidi.

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

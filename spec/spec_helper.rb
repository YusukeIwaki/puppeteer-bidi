# frozen_string_literal: true

require "puppeteer/bidi"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # spec/integration/* should be run as type=:integration
  config.define_derived_metadata(file_path: %r{spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  helper_module = Module.new do
    def headless_mode?
      !%w[0 false].include?(ENV['HEADLESS'])
    end

    def with_browser(**options)
      options[:headless] = headless_mode?
      browser = Puppeteer::Bidi.launch(**options)
      yield(browser)
    ensure
      browser&.close
    end
  end
  config.include helper_module, type: :integration
end

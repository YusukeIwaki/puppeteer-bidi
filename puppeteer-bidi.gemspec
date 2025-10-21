# frozen_string_literal: true

require_relative "lib/puppeteer/bidi/version"

Gem::Specification.new do |spec|
  spec.name = "puppeteer-bidi"
  spec.version = Puppeteer::Bidi::VERSION
  spec.authors = ["YusukeIwaki"]
  spec.email = ["iwaki@i3-systems.com"]

  spec.summary = "A Ruby port of Puppeteer using WebDriver BiDi protocol for Firefox automation"
  spec.description = "Puppeteer-BiDi is a Ruby implementation of Puppeteer that uses the WebDriver BiDi protocol to automate Firefox browsers. Unlike puppeteer-ruby which uses Chrome DevTools Protocol (CDP), this gem focuses on BiDi protocol support for cross-browser automation, particularly targeting Firefox."
  spec.homepage = "https://github.com/YusukeIwaki/puppeteer-bidi"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/YusukeIwaki/puppeteer-bidi"
  spec.metadata["changelog_uri"] = "https://github.com/YusukeIwaki/puppeteer-bidi/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end

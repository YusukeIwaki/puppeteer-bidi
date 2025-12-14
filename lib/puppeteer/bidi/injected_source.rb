# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Puppeteer's injected utilities (Poller classes, Deferred, etc.)
    # Source: https://unpkg.com/puppeteer-core@24.31.0/lib/esm/puppeteer/generated/injected.js
    # Version: puppeteer-core@24.31.0
    #
    # To update this file, run:
    #   bundle exec ruby scripts/update_injected_source.rb
    #
    # This script provides:
    # - RAFPoller: requestAnimationFrame-based polling
    # - MutationPoller: MutationObserver-based polling
    # - IntervalPoller: setInterval-based polling
    # - Deferred: Promise wrapper
    # - createFunction: Creates function from string
    # - Various query selector utilities
    PUPPETEER_INJECTED_SOURCE = File.read(File.join(__dir__, 'injected.js')).freeze
  end
end

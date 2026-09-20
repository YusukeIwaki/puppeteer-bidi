# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi do
  describe ".launch_browser_instance" do
    it "forwards logger, headers, and ws_options to Browser.launch" do
      allow(Puppeteer::Bidi::Browser).to receive(:launch)

      logger = ->(_prefix) { nil }
      headers = { "Authorization" => "top-level" }
      ws_options = { keep_alive: true }

      described_class.launch_browser_instance(logger: logger, headers: headers, ws_options: ws_options)

      expect(Puppeteer::Bidi::Browser).to have_received(:launch).with(
        hash_including(logger: logger, headers: headers, ws_options: ws_options)
      )
    end
  end

  describe ".connect_to_browser_instance" do
    it "forwards logger, headers, and ws_options to Browser.connect" do
      allow(Puppeteer::Bidi::Browser).to receive(:connect)

      logger = ->(_prefix) { nil }
      headers = { "Authorization" => "top-level" }
      ws_options = { keep_alive: true }

      described_class.connect_to_browser_instance(
        "ws://127.0.0.1:9222/session",
        logger: logger,
        headers: headers,
        ws_options: ws_options
      )

      expect(Puppeteer::Bidi::Browser).to have_received(:connect).with(
        "ws://127.0.0.1:9222/session",
        hash_including(logger: logger, headers: headers, ws_options: ws_options)
      )
    end
  end
end

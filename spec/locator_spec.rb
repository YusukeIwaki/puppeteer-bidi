# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Locator do
  describe ".race" do
    it "does not crash for an empty locator list and falls back to a no-op logger" do
      race = described_class.race([])

      expect(race).to be_a(Puppeteer::Bidi::RaceLocator)
      expect(race.logger.call(Puppeteer::Bidi::Debug::ERROR)).to be_nil
    end

    it "inherits the logger of the first locator" do
      entries = []
      logger = ->(prefix) { ->(*args) { entries << [prefix, args] } }
      first = described_class.new(logger)

      race = described_class.race([first, described_class.new])

      expect(race.logger).to be(logger)
    end

    it "defaults to a no-op logger" do
      expect(described_class.new.logger.call(Puppeteer::Bidi::Debug::ERROR)).to be_nil
    end
  end

  describe "logger propagation" do
    let(:logger) { ->(_prefix) { ->(*args) { args } } }
    let(:page) do
      Puppeteer::Bidi::Page.new(
        double("browser_context", logger: logger, logger_explicit: true),
        double("core_browsing_context", closed?: false)
      )
    end

    it "inherits the page logger in NodeLocator" do
      locator = page.locator("button")

      expect(locator).to be_a(Puppeteer::Bidi::NodeLocator)
      expect(locator.logger).to be(logger)
    end

    it "inherits the page logger in FunctionLocator" do
      locator = page.locator(function: "() => document.body")

      expect(locator).to be_a(Puppeteer::Bidi::FunctionLocator)
      expect(locator.logger).to be(logger)
    end

    it "inherits the delegate logger in filtered locators" do
      locator = page.locator("button").filter(->(handle) { handle })

      expect(locator).to be_a(Puppeteer::Bidi::FilteredLocator)
      expect(locator.logger).to be(logger)
    end
  end
end

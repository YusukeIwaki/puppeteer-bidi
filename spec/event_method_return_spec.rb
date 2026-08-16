# frozen_string_literal: true

require "spec_helper"

RSpec.describe "event method return values" do # rubocop:disable Metrics/BlockLength
  let(:listener) { proc { |_event| } }

  describe Puppeteer::Bidi::Browser do
    subject(:browser) { described_class.allocate }

    before do
      browser.instance_variable_set(:@emitter, Puppeteer::Bidi::Core::EventEmitter.new)
      browser.instance_variable_set(:@connection, Puppeteer::Bidi::Core::EventEmitter.new)
    end

    it "returns the browser for target and protocol events" do
      %i[targetcreated browsingContext.load].each do |event|
        expect(browser.on(event, &listener)).to equal(browser)
        expect(browser.once(event, &listener)).to equal(browser)
        expect(browser.off(event, &listener)).to equal(browser)
      end
    end
  end

  describe Puppeteer::Bidi::BrowserContext do
    subject(:browser_context) { described_class.allocate }

    before do
      browser_context.instance_variable_set(:@emitter, Puppeteer::Bidi::Core::EventEmitter.new)
    end

    it "returns the browser context" do
      expect(browser_context.on(:targetcreated, &listener)).to equal(browser_context)
      expect(browser_context.once(:targetcreated, &listener)).to equal(browser_context)
      expect(browser_context.off(:targetcreated, &listener)).to equal(browser_context)
    end
  end

  describe Puppeteer::Bidi::Page do
    subject(:page) { described_class.allocate }

    before do
      page.instance_variable_set(:@emitter, Puppeteer::Bidi::Core::EventEmitter.new)
      page.instance_variable_set(:@request_handlers, ObjectSpace::WeakMap.new)
    end

    it "returns the page" do
      expect(page.on(:load, &listener)).to equal(page)
      expect(page.once(:load, &listener)).to equal(page)
      expect(page.off(:load, &listener)).to equal(page)
    end

    it "returns the page for request listeners" do
      expect(page.on(:request, &listener)).to equal(page)
      expect(page.off(:request, &listener)).to equal(page)
    end
  end
end

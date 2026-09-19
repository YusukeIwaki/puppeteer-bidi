# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::QueryHandler do
  subject(:dispatcher) { described_class.instance }

  describe "#get_query_handler_and_selector" do
    it "keeps pure CSS on the CSS handler with mutation polling" do
      result = dispatcher.get_query_handler_and_selector("div.foo")

      expect(result.query_handler).to be(Puppeteer::Bidi::CSSQueryHandler)
      expect(result.updated_selector).to eq("div.foo")
      expect(result.polling).to eq("mutation")
    end

    it "uses raf polling for CSS with pseudo-classes" do
      result = dispatcher.get_query_handler_and_selector("div:hover")

      expect(result.query_handler).to be(Puppeteer::Bidi::CSSQueryHandler)
      expect(result.polling).to eq("raf")
    end

    it "dispatches pierce selectors to the P handler with the parsed JSON form" do
      result = dispatcher.get_query_handler_and_selector("div >>> h1")

      expect(result.query_handler).to be(Puppeteer::Bidi::PQueryHandler)
      expect(result.updated_selector).to eq('[[["div"],">>>",["h1"]]]')
      expect(result.polling).to eq("mutation")
    end

    it "uses raf polling for aria queries" do
      result = dispatcher.get_query_handler_and_selector("::-p-aria(Submit)")

      expect(result.query_handler).to be(Puppeteer::Bidi::PQueryHandler)
      expect(result.polling).to eq("raf")
    end

    it "falls back to plain CSS when the selector cannot be parsed" do
      result = dispatcher.get_query_handler_and_selector('div\\')

      expect(result.query_handler).to be(Puppeteer::Bidi::CSSQueryHandler)
      expect(result.updated_selector).to eq('div\\')
      expect(result.polling).to eq("mutation")
    end
  end
end

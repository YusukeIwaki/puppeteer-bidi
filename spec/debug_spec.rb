# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Debug do
  describe "DEBUG_PREFIXES" do
    it "matches the upstream BiDi send/receive/error prefixes" do
      expect(described_class::BIDI_SEND).to eq("puppeteer:webDriverBiDi:SEND \u25BA")
      expect(described_class::BIDI_RECEIVE).to eq("puppeteer:webDriverBiDi:RECV \u25C0")
      expect(described_class::ERROR).to eq("puppeteer:error")
      expect(described_class::DEBUG_PREFIXES).to eq(
        {
          bidi_send: "puppeteer:webDriverBiDi:SEND \u25BA",
          bidi_receive: "puppeteer:webDriverBiDi:RECV \u25C0",
          error: "puppeteer:error"
        }
      )
    end
  end

  describe ".default_logger" do
    around do |example|
      saved = {
        "DEBUG_BIDI_COMMAND" => ENV["DEBUG_BIDI_COMMAND"],
        "DEBUG_PROTOCOL" => ENV["DEBUG_PROTOCOL"]
      }
      ENV.delete("DEBUG_BIDI_COMMAND")
      ENV.delete("DEBUG_PROTOCOL")
      example.run
      saved.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end

    it "returns nil for every channel when no debug env var is set" do
      logger = described_class.default_logger
      expect(logger.call(described_class::BIDI_SEND)).to be_nil
      expect(logger.call(described_class::BIDI_RECEIVE)).to be_nil
      expect(logger.call(described_class::ERROR)).to be_nil
    end

    it "enables protocol channels via DEBUG_BIDI_COMMAND" do
      ENV["DEBUG_BIDI_COMMAND"] = "1"
      logger = described_class.default_logger
      expect(logger.call(described_class::BIDI_SEND)).not_to be_nil
      expect(logger.call(described_class::BIDI_RECEIVE)).not_to be_nil
      expect(logger.call(described_class::ERROR)).not_to be_nil
    end

    it "enables protocol channels via DEBUG_PROTOCOL without enabling the error channel" do
      ENV["DEBUG_PROTOCOL"] = "true"
      logger = described_class.default_logger
      expect(logger.call(described_class::BIDI_SEND)).not_to be_nil
      expect(logger.call(described_class::BIDI_RECEIVE)).not_to be_nil
      expect(logger.call(described_class::ERROR)).to be_nil
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Transport do
  describe "logger" do
    let(:logged) { Hash.new { |hash, key| hash[key] = [] } }
    let(:logger) do
      logged_store = logged
      ->(prefix) { ->(*args) { logged_store[prefix] << args } }
    end

    it "routes protocol debug output through the configured logger" do
      transport = described_class.new("ws://127.0.0.1:9222/session", logger: logger)
      transport.send(:debug_print_send, { "id" => 1, "method" => "session.status" })
      transport.send(:debug_print_receive, { "id" => 1, "type" => "success" })

      expect(logged[Puppeteer::Bidi::Debug::BIDI_SEND].size).to eq(1)
      expect(logged[Puppeteer::Bidi::Debug::BIDI_SEND].first.first).to include("session.status")
      expect(logged[Puppeteer::Bidi::Debug::BIDI_RECEIVE].size).to eq(1)
    end

    it "falls back to warn for diagnostics when the logger disables the error channel" do
      transport = described_class.new("ws://127.0.0.1:9222/session", logger: ->(_prefix) { nil })
      expect { transport.send(:log_error, "boom") }.to output(/boom/).to_stderr
    end
  end

  describe "#url" do
    it "preserves the supplied WebSocket URL" do
      urls = [
        "ws://127.0.0.1:9222",
        "ws://127.0.0.1:9222/",
        "ws://127.0.0.1:9222/session",
        "ws://127.0.0.1:9222/session/2f9e1b1c-0f1a-4f6d-9c1e-6a1b2c3d4e5f",
        "wss://example.test?token=test-token"
      ]

      aggregate_failures do
        urls.each do |url|
          expect(described_class.new(url).url).to eq(url)
        end
      end
    end
  end
end

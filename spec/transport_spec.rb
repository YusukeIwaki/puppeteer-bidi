# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Transport do
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

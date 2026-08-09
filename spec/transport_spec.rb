# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Transport do
  subject(:transport) { described_class.new(url) }

  describe "#url" do
    context "with a bare WebSocket URL" do
      let(:url) { "ws://127.0.0.1:9222" }

      it "appends the session endpoint" do
        expect(transport.url).to eq("ws://127.0.0.1:9222/session")
      end
    end

    context "with a trailing slash" do
      let(:url) { "ws://127.0.0.1:9222/" }

      it "appends the session endpoint once" do
        expect(transport.url).to eq("ws://127.0.0.1:9222/session")
      end
    end

    context "with the session endpoint already present" do
      let(:url) { "ws://127.0.0.1:9222/session" }

      it "keeps the URL unchanged" do
        expect(transport.url).to eq("ws://127.0.0.1:9222/session")
      end
    end

    context "with a session id, as geckodriver reports it" do
      let(:url) { "ws://127.0.0.1:9222/session/2f9e1b1c-0f1a-4f6d-9c1e-6a1b2c3d4e5f" }

      it "keeps the URL unchanged" do
        expect(transport.url).to eq("ws://127.0.0.1:9222/session/2f9e1b1c-0f1a-4f6d-9c1e-6a1b2c3d4e5f")
      end
    end
  end
end

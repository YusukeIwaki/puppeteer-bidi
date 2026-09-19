# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Core::BrowsingContext do
  let(:captured) { {} }
  let(:session) do
    captured_store = captured
    session = double("session")
    allow(session).to receive(:on)
    allow(session).to receive(:async_send_command) do |method, params|
      captured_store[:method] = method
      captured_store[:params] = params
      Async { { "screencast" => "cast-1", "path" => "/tmp/cast.webm" } }
    end
    session
  end

  subject(:context) do
    user_context = double(
      "user_context",
      browser: double("browser", session: session)
    )
    described_class.new(user_context, nil, "ctx-1", "about:blank", nil, nil)
  end

  describe "#start_screencast" do
    it "omits absent keys from the protocol payload" do
      context.start_screencast(audio: nil, video: nil).wait

      expect(captured[:method]).to eq("browsingContext.startScreencast")
      expect(captured[:params]).to eq({ context: "ctx-1" })
    end

    it "sends audio and video constraints as given" do
      context.start_screencast(
        audio: true,
        video: { width: 800, height: 600, frameRate: 30 }
      ).wait

      expect(captured[:params]).to eq(
        {
          context: "ctx-1",
          audio: true,
          video: { width: 800, height: 600, frameRate: 30 },
        }
      )
    end
  end

  describe "#stop_screencast" do
    it "sends the screencast id" do
      context.stop_screencast("cast-1").wait

      expect(captured[:method]).to eq("browsingContext.stopScreencast")
      expect(captured[:params]).to eq({ screencast: "cast-1" })
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::JSHandle do
  describe "#dispose" do
    it "logs disown failures to the connection error logger instead of raising" do
      entries = []
      logger = ->(prefix) { ->(error) { entries << [prefix, error.message] } }
      connection = double("connection", logger: logger)
      session = double("session", connection: connection)
      realm = double("core_realm", session: session)
      allow(realm).to receive(:disown).and_raise(StandardError, "navigated away")

      handle = described_class.new(realm, { "type" => "object", "handle" => "1" })

      expect { handle.dispose }.not_to raise_error
      expect(handle.disposed?).to be(true)
      expect(entries).to eq([[Puppeteer::Bidi::Debug::ERROR, "navigated away"]])
    end

    it "disowns the remote reference without logging on success" do
      entries = []
      logger = ->(prefix) { ->(error) { entries << [prefix, error.message] } }
      connection = double("connection", logger: logger)
      session = double("session", connection: connection)
      realm = double("core_realm", session: session)
      allow(realm).to receive(:disown).with(["1"]).and_return(Async { nil })

      handle = described_class.new(realm, { "type" => "object", "handle" => "1" })
      handle.dispose

      expect(handle.disposed?).to be(true)
      expect(entries).to be_empty
    end
  end
end

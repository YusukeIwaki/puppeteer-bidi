# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Connection do
  subject(:connection) { described_class.new(transport) }

  let(:transport) { RecordingTransport.new }
  let(:event) { { "method" => "log.entryAdded", "params" => { "text" => "hello" } } }

  describe "#on" do
    it "returns the listener" do
      listener = proc { |_params| }

      expect(connection.on("log.entryAdded", &listener)).to eq(listener)
    end

    it "hands the returned listener back to #off" do
      entries = []
      listener = connection.on("log.entryAdded") { |params| entries << params }

      connection.off("log.entryAdded", &listener)
      transport.receive(event)

      expect(entries).to be_empty
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Connection do
  subject(:connection) { described_class.new(RecordingTransport.new) }

  let(:listener) { proc { |_params| } }

  it "returns itself from #on and #off" do
    expect(connection.on("log.entryAdded", &listener)).to equal(connection)
    expect(connection.off("log.entryAdded", &listener)).to equal(connection)
    expect(connection.off("unknown.event", &listener)).to equal(connection)
  end
end

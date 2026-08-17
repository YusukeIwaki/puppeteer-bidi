# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Connection::ProtocolError do
  subject(:connection) { Puppeteer::Bidi::Connection.new(transport) }

  let(:transport) { RecordingTransport.new }

  let(:error) do
    task = connection.async_send_command("script.evaluate")
    transport.receive("id" => transport.sent.first[:id], "type" => "error",
                      "error" => "no such frame", "message" => "Browsing context no longer exists")
    task.wait
    nil
  rescue described_class => e
    e
  end

  it "exposes the code the browser sent" do
    expect(error.code).to eq("no such frame")
  end

  it "keeps the message the browser sent" do
    expect(error.message).to eq("BiDi error (script.evaluate): Browsing context no longer exists")
  end

  context "when the connection itself raised" do
    subject(:error) { described_class.new("Connection is closed") }

    it "reports no code" do
      expect(error.code).to be_nil
    end
  end
end

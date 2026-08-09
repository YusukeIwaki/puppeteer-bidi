# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Connection do
  subject(:connection) { described_class.new(transport) }

  let(:transport) { RecordingTransport.new }

  def pending_command_count
    connection.instance_variable_get(:@pending_commands).size
  end

  describe "#async_send_command" do
    context "when the send fails" do
      let(:transport) { RecordingTransport.new(send_error: Puppeteer::Bidi::Transport::ClosedError.new("closed")) }

      before do
        connection.async_send_command("session.status").wait
      rescue Puppeteer::Bidi::Transport::ClosedError
        nil
      end

      it "leaves no command pending" do
        expect(pending_command_count).to eq(0)
      end
    end

    context "when the send succeeds" do
      before { connection.async_send_command("session.status") }

      # Answer it, or the command holds the suite open for the default 30s timeout.
      after { transport.reply(transport.sent.first[:id], {}) }

      it "holds the command until the reply arrives" do
        expect(pending_command_count).to eq(1)
      end
    end
  end
end

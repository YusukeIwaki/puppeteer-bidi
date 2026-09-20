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

  describe "logger" do
    let(:logged) { Hash.new { |hash, key| hash[key] = [] } }
    let(:logger) do
      logged_store = logged
      ->(prefix) { ->(*args) { logged_store[prefix] << args } }
    end

    subject(:connection) { described_class.new(transport, logger: logger) }

    it "logs outgoing commands with the BiDi send prefix" do
      task = connection.async_send_command("session.status")
      transport.reply(transport.sent.first[:id], {})
      task.wait

      sends = logged[Puppeteer::Bidi::Debug::BIDI_SEND]
      expect(sends.size).to eq(1)
      expect(sends.first.first).to include("session.status")
    end

    it "logs incoming responses with the BiDi receive prefix exactly once" do
      task = connection.async_send_command("session.status")
      transport.reply(transport.sent.first[:id], { "ready" => true })
      task.wait

      receives = logged[Puppeteer::Bidi::Debug::BIDI_RECEIVE]
      expect(receives.size).to eq(1)
      expect(JSON.parse(receives.first.first)).to include("id" => transport.sent.first[:id])
    end

    it "logs events with the BiDi receive prefix exactly once" do
      connection
      transport.receive({ "method" => "browsingContext.load", "params" => {} })

      receives = logged[Puppeteer::Bidi::Debug::BIDI_RECEIVE]
      expect(receives.size).to eq(1)
      expect(JSON.parse(receives.first.first)).to include("method" => "browsingContext.load")
    end

    it "logs malformed messages with the error prefix instead of warning" do
      connection
      expect { transport.receive({ "unexpected" => true }) }.not_to output.to_stderr
      errors = logged[Puppeteer::Bidi::Debug::ERROR]
      expect(errors.size).to eq(1)
      expect(errors.first.first).to include("Unknown BiDi message format")
    end

    context "when the logger disables a channel" do
      let(:logger) { ->(_prefix) { nil } }

      it "stays silent instead of warning" do
        connection
        expect { transport.receive({ "unexpected" => true }) }.not_to output.to_stderr
        expect(logged).to be_empty
      end
    end

    context "without an explicit logger" do
      subject(:connection) { described_class.new(transport) }

      it "falls back to warn for diagnostics" do
        connection
        expect { transport.receive({ "unexpected" => true }) }
          .to output(/Unknown BiDi message format/).to_stderr
      end
    end
  end
end

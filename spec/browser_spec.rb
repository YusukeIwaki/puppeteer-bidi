# frozen_string_literal: true

require "spec_helper"

# Script only wire responses; exercise the real
# Connection/Session/Core::Browser/Browser graph.
class ScriptedBrowserTransport < RecordingTransport
  def async_send_message(message)
    super
    result = case message[:method]
             when "session.new"
               { "sessionId" => "session-1", "capabilities" => {} }
             when "browser.getUserContexts"
               { "userContexts" => [{ "userContext" => "default" }] }
             when "browsingContext.getTree"
               { "contexts" => [] }
             else
               {}
             end
    reply(message[:id], result)
    Async { nil }
  end
end

# Scripted endpoint for Browser.connect: configurable session.status,
# plus the session-creation flow. `connect` resolves immediately since
# no real socket exists.
class ScriptedConnectTransport < RecordingTransport
  def initialize(status_response:, status_error: nil)
    super()
    @status_response = status_response
    @status_error = status_error
  end

  def connect
    Async { nil }
  end

  def async_send_message(message)
    super
    case message[:method]
    when "session.status"
      if @status_error
        receive({ "id" => message[:id], "type" => "error", "error" => "unknown command", "message" => @status_error })
      else
        reply(message[:id], @status_response)
      end
    when "session.new"
      reply(message[:id], { "sessionId" => "session-1", "capabilities" => {} })
    when "browser.getUserContexts"
      reply(message[:id], { "userContexts" => [{ "userContext" => "default" }] })
    when "browsingContext.getTree"
      reply(message[:id], { "contexts" => [] })
    else
      reply(message[:id], {})
    end
    Async { nil }
  end
end

RSpec.describe Puppeteer::Bidi::Browser do
  def build_browser(logger = ->(_) { nil })
    transport = ScriptedBrowserTransport.new
    connection = Puppeteer::Bidi::Connection.new(transport, logger: logger)
    [Puppeteer::Bidi::Browser.create(connection: connection), transport]
  end

  describe ".connect" do
    it "accepts a successful status response even when the endpoint reports not ready" do
      transport = ScriptedConnectTransport.new(
        status_response: { "ready" => false, "message" => "Session already started" }
      )
      allow(Puppeteer::Bidi::Transport).to receive(:new).and_return(transport)

      browser = described_class.connect("ws://127.0.0.1:4444/session")

      expect(browser.connected?).to be(true)
      expect(transport.sent.map { |command| command[:method] }).to include("session.status", "session.new")
    ensure
      browser&.disconnect
    end

    it "rejects endpoints that fail the status check" do
      transport = ScriptedConnectTransport.new(status_response: {}, status_error: "unknown command")
      allow(Puppeteer::Bidi::Transport).to receive(:new).and_return(transport)

      expect { described_class.connect("ws://127.0.0.1:4444/session") }
        .to raise_error(Puppeteer::Bidi::Error, /WebDriver BiDi endpoint is not available/)
    end
  end

  describe "#connected?" do
    it "reports disconnected after Browser#close" do
      browser, _transport = build_browser

      expect(browser.connected?).to be(true)
      browser.close
      expect(browser.connection.closed?).to be(true)
      expect(browser.connected?).to be(false)
    end

    it "reports disconnected after explicit Browser#disconnect" do
      browser, _transport = build_browser

      browser.disconnect

      expect(browser.connection.closed?).to be(true)
      expect(browser.connected?).to be(false)
    end
  end
end

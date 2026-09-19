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

RSpec.describe Puppeteer::Bidi::Browser do
  def build_browser(logger = ->(_) { nil })
    transport = ScriptedBrowserTransport.new
    connection = Puppeteer::Bidi::Connection.new(transport, logger: logger)
    [Puppeteer::Bidi::Browser.create(connection: connection), transport]
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

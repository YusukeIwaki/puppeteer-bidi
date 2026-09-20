# frozen_string_literal: true

require "spec_helper"

# Script only wire responses; exercise the real
# Connection/Session/Core::Browser/WindowRealm/JSHandle graph.
class DisownErrorTransport < RecordingTransport
  def async_send_message(message)
    super
    if message[:method] == "script.disown"
      receive({ "id" => message[:id], "type" => "error", "error" => "no such handle", "message" => "disown failed" })
    else
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
    end
    Async { nil }
  end
end

RSpec.describe Puppeteer::Bidi::JSHandle do
  describe "#dispose" do
    it "logs a real WindowRealm disown error with the original exception" do
      errors = []
      logger = lambda do |prefix|
        next nil unless prefix == Puppeteer::Bidi::Debug::ERROR

        ->(error) { errors << error }
      end
      transport = DisownErrorTransport.new
      connection = Puppeteer::Bidi::Connection.new(transport, logger: logger)
      browser = Puppeteer::Bidi::Browser.create(connection: connection)
      context = Struct.new(:user_context, :id).new(browser.default_browser_context.user_context, "context-1")
      realm = Puppeteer::Bidi::Core::WindowRealm.new(context)

      handle = described_class.new(realm, { "type" => "object", "handle" => "handle-1" })
      handle.dispose

      expect(transport.sent.map { |command| command[:method] }).to include("script.disown")
      expect(handle.disposed?).to be(true)
      expect(errors.map(&:message)).to eq(["BiDi error (script.disown): disown failed"])
    ensure
      browser&.disconnect
    end

    it "disowns the remote reference without logging on success" do
      realm = double("core_realm")
      allow(realm).to receive(:disown).with(["1"]).and_return(Async { nil })

      handle = described_class.new(realm, { "type" => "object", "handle" => "1" })
      handle.dispose

      expect(handle.disposed?).to be(true)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

class ReactorRunnerLifecycleTransport < RecordingTransport
  def connect
    Async { nil }
  end

  def async_send_message(message)
    super
    result = case message[:method]
             when "session.status" then { "ready" => true, "message" => "" }
             when "session.new" then { "sessionId" => "id", "capabilities" => {} }
             when "browser.getUserContexts" then { "userContexts" => [{ "userContext" => "default" }] }
             when "browsingContext.getTree" then { "contexts" => [] }
             else {}
             end
    reply(message[:id], result)
    Async { nil }
  end
end

class ReactorRunnerDummyTarget
  def connected?
    true
  end
end

RSpec.describe Puppeteer::Bidi::ReactorRunner do
  def stub_lifecycle_transport
    allow(Puppeteer::Bidi::Transport).to receive(:new) { ReactorRunnerLifecycleTransport.new }
  end

  describe "public connect factory outside Async" do
    it "reports lifecycle predicates while open" do
      stub_lifecycle_transport
      result = Thread.new do
        browser = Puppeteer::Bidi.connect_to_browser_instance("ws://scripted")
        begin
          async = begin
            !Async::Task.current.nil?
          rescue RuntimeError, NoMethodError
            false
          end
          {
            async: async,
            owns_runner: browser.instance_variable_get(:@owns_runner),
            connected: browser.connected?,
            closed: browser.closed?,
            disconnected: browser.disconnected?,
          }
        ensure
          browser&.close
        end
      end.value

      expect(result[:async]).to be(false)
      expect(result[:owns_runner]).to be(true)
      expect(result[:connected]).to be(true)
      expect(result[:closed]).to be(false)
      expect(result[:disconnected]).to be(false)
    end

    it "allows predicates after disconnect and rejects remote operations" do
      stub_lifecycle_transport
      result = Thread.new do
        browser = Puppeteer::Bidi.connect_to_browser_instance("ws://scripted")
        begin
          before = browser.connected?
          browser.disconnect
          remote_errors = []
          begin
            browser.new_page
          rescue StandardError => error
            remote_errors << error
          end
          begin
            browser.status
          rescue StandardError => error
            remote_errors << error
          end
          {
            before: before,
            connected: browser.connected?,
            closed: browser.closed?,
            disconnected: browser.disconnected?,
            remote_errors: remote_errors,
            second_disconnect: browser.disconnect,
            close_after_disconnect: browser.close,
          }
        ensure
          browser&.close
        end
      end.value

      expect(result[:before]).to be(true)
      expect(result[:connected]).to be(false)
      expect(result[:closed]).to be(false)
      expect(result[:disconnected]).to be(true)
      expect(result[:remote_errors].size).to eq(2)
      expect(result[:remote_errors].map(&:class)).to all(eq(Puppeteer::Bidi::Error))
      expect(result[:remote_errors].map(&:message)).to all(eq("ReactorRunner is closed"))
      expect(result[:second_disconnect]).to be_nil
      expect(result[:close_after_disconnect]).to be_nil
    end

    it "allows predicates after close and rejects remote operations" do
      stub_lifecycle_transport
      result = Thread.new do
        browser = Puppeteer::Bidi.connect_to_browser_instance("ws://scripted")
        begin
          before = browser.connected?
          browser.close
          remote_errors = []
          begin
            browser.new_page
          rescue StandardError => error
            remote_errors << error
          end
          begin
            browser.status
          rescue StandardError => error
            remote_errors << error
          end
          {
            before: before,
            connected: browser.connected?,
            closed: browser.closed?,
            disconnected: browser.disconnected?,
            remote_errors: remote_errors,
            second_close: browser.close,
            disconnect_after_close: browser.disconnect,
          }
        ensure
          browser&.close
        end
      end.value

      expect(result[:before]).to be(true)
      expect(result[:connected]).to be(false)
      expect(result[:closed]).to be(true)
      expect(result[:disconnected]).to be(true)
      expect(result[:remote_errors].size).to eq(2)
      expect(result[:remote_errors].map(&:class)).to all(eq(Puppeteer::Bidi::Error))
      expect(result[:remote_errors].map(&:message)).to all(eq("ReactorRunner is closed"))
      expect(result[:second_close]).to be_nil
      expect(result[:disconnect_after_close]).to be_nil
    end

    it "preserves true connected? when the runner closes without browser disconnect" do
      stub_lifecycle_transport
      result = Thread.new do
        browser = Puppeteer::Bidi.connect_to_browser_instance("ws://scripted")
        begin
          open_connected = browser.connected?
          runner = browser.instance_variable_get(:@runner)
          runner.close
          remote_error = begin
            browser.new_page
            nil
          rescue StandardError => error
            error
          end
          {
            open_connected: open_connected,
            connected: browser.connected?,
            closed: browser.closed?,
            disconnected: browser.disconnected?,
            remote_error: remote_error,
          }
        ensure
          browser&.close
        end
      end.value

      expect(result[:open_connected]).to be(true)
      expect(result[:connected]).to be(true)
      expect(result[:closed]).to be(false)
      expect(result[:disconnected]).to be(false)
      expect(result[:remote_error]).to be_a(Puppeteer::Bidi::Error)
      expect(result[:remote_error].message).to eq("ReactorRunner is closed")
    end
  end

  describe "Proxy closed-runner dispatch" do
    it "rejects arbitrary targets instead of returning hardcoded false" do
      runner = described_class.new
      proxy = described_class::Proxy.new(runner, ReactorRunnerDummyTarget.new, owns_runner: true)
      expect(proxy.connected?).to be(true)
      runner.close
      expect { proxy.connected? }.to raise_error(Puppeteer::Bidi::Error, "ReactorRunner is closed")
    end

    it "allows predicates through a public BrowserContext#browser alias after disconnect" do
      stub_lifecycle_transport
      result = Thread.new do
        browser = Puppeteer::Bidi.connect_to_browser_instance("ws://scripted")
        begin
          browser_alias = browser.default_browser_context.browser
          owns_runner = browser_alias.instance_variable_get(:@owns_runner)
          same_target = browser_alias.__getobj__.equal?(browser.__getobj__)
          before = browser_alias.connected?
          browser.disconnect
          remote_error = begin
            browser_alias.new_page
            nil
          rescue StandardError => error
            error
          end
          {
            owns_runner: owns_runner,
            same_target: same_target,
            before: before,
            connected: browser_alias.connected?,
            closed: browser_alias.closed?,
            disconnected: browser_alias.disconnected?,
            main_connected: browser.connected?,
            main_closed: browser.closed?,
            main_disconnected: browser.disconnected?,
            remote_error: remote_error,
          }
        ensure
          browser&.close
        end
      end.value

      expect(result[:owns_runner]).to be(false)
      expect(result[:same_target]).to be(true)
      expect(result[:before]).to be(true)
      expect(result[:connected]).to be(false)
      expect(result[:closed]).to be(false)
      expect(result[:disconnected]).to be(true)
      expect(result[:main_connected]).to be(false)
      expect(result[:main_closed]).to be(false)
      expect(result[:main_disconnected]).to be(true)
      expect(result[:remote_error]).to be_a(Puppeteer::Bidi::Error)
      expect(result[:remote_error].message).to eq("ReactorRunner is closed")
    end

    it "allows predicates through a public BrowserContext#browser alias after close" do
      stub_lifecycle_transport
      result = Thread.new do
        browser = Puppeteer::Bidi.connect_to_browser_instance("ws://scripted")
        begin
          browser_alias = browser.default_browser_context.browser
          owns_runner = browser_alias.instance_variable_get(:@owns_runner)
          same_target = browser_alias.__getobj__.equal?(browser.__getobj__)
          before = browser_alias.connected?
          browser.close
          remote_error = begin
            browser_alias.new_page
            nil
          rescue StandardError => error
            error
          end
          {
            owns_runner: owns_runner,
            same_target: same_target,
            before: before,
            connected: browser_alias.connected?,
            closed: browser_alias.closed?,
            disconnected: browser_alias.disconnected?,
            main_connected: browser.connected?,
            main_closed: browser.closed?,
            main_disconnected: browser.disconnected?,
            remote_error: remote_error,
          }
        ensure
          browser&.close
        end
      end.value

      expect(result[:owns_runner]).to be(false)
      expect(result[:same_target]).to be(true)
      expect(result[:before]).to be(true)
      expect(result[:connected]).to be(false)
      expect(result[:closed]).to be(true)
      expect(result[:disconnected]).to be(true)
      expect(result[:main_connected]).to be(false)
      expect(result[:main_closed]).to be(true)
      expect(result[:main_disconnected]).to be(true)
      expect(result[:remote_error]).to be_a(Puppeteer::Bidi::Error)
      expect(result[:remote_error].message).to eq("ReactorRunner is closed")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Transport do
  # Stands in for the real WebSocket connection: blocks in #read until
  # released, records pings, and lets the example fire pong callbacks.
  class StubWSConnection
    attr_reader :ping_count
    attr_writer :pong_handler

    def initialize
      @ping_count = 0
      @closed = false
      @read_gate = Async::Promise.new
    end

    def read
      @read_gate.wait
      nil
    end

    def release_read
      @read_gate.resolve(true) unless @read_gate.resolved?
    end

    def send_ping
      @ping_count += 1
    end

    def pong!
      @pong_handler&.call
    end

    def write(_data); end

    def flush; end

    def close
      @closed = true
      release_read
    end

    def closed?
      @closed
    end
  end

  let(:stubbed_connection) { StubWSConnection.new }
  let(:captured_options) { {} }
  let(:connected_transports) { [] }

  before do
    fake = stubbed_connection
    captured = captured_options
    allow(Async::WebSocket::Client).to receive(:connect) do |_endpoint, **opts, &block|
      captured.merge!(opts)
      block.call(fake)
    end
  end

  # Release the stubbed connection so the suite reactor can shut down.
  after do
    connected_transports.each(&:close)
  end

  def connect_transport(transport)
    connected_transports << transport
    transport.connect.wait
  end

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      Async::Task.current.sleep(0.01)
    end
  end

  describe "ws_options headers" do
    it "passes handshake headers through, with nested headers winning over top-level headers" do
      transport = described_class.new(
        "ws://127.0.0.1:9222/session",
        headers: { "Authorization" => "top-level" },
        ws_options: { headers: { "Authorization" => "nested" } },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      expect(captured_options[:headers]).to eq({ "Authorization" => "nested" })
    end

    it "uses top-level headers when nested headers are absent" do
      transport = described_class.new(
        "ws://127.0.0.1:9222/session",
        headers: { "Authorization" => "top-level" },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      expect(captured_options[:headers]).to eq({ "Authorization" => "top-level" })
    end

    it "sends no headers by default" do
      transport = described_class.new("ws://127.0.0.1:9222/session", logger: ->(_prefix) { nil })
      connect_transport(transport)

      expect(captured_options).not_to have_key(:headers)
    end
  end

  describe "ws_options keepalive" do
    it "is disabled by default" do
      transport = described_class.new("ws://127.0.0.1:9222/session", logger: ->(_prefix) { nil })

      expect(transport.keep_alive_enabled?).to be(false)

      connect_transport(transport)
      expect(captured_options).not_to have_key(:handler)
    end

    it "uses 30s as the default interval, matching upstream" do
      expect(described_class::DEFAULT_KEEP_ALIVE_INTERVAL_MS).to eq(30_000)
    end

    it "closes locally when the pong for the previous ping never arrives" do
      transport = described_class.new(
        "ws://127.0.0.1:9222/session",
        ws_options: { keep_alive: true, keep_alive_interval_ms: 50 },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      expect(captured_options[:handler]).to eq(described_class::KeepAliveConnection)

      wait_until { transport.closed? }

      expect(stubbed_connection.ping_count).to be >= 1
      expect(stubbed_connection.closed?).to be(true)
    end

    it "keeps the connection open while pongs arrive" do
      transport = described_class.new(
        "ws://127.0.0.1:9222/session",
        ws_options: { keep_alive: true, keep_alive_interval_ms: 50 },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      wait_until { stubbed_connection.ping_count >= 1 }
      stubbed_connection.pong!
      wait_until { stubbed_connection.ping_count >= 2 }
      stubbed_connection.pong!

      expect(transport.closed?).to be(false)
      expect(stubbed_connection.closed?).to be(false)

      transport.close
      expect(transport.closed?).to be(true)
    end
  end

  describe "logger" do
    let(:logged) { Hash.new { |hash, key| hash[key] = [] } }
    let(:logger) do
      logged_store = logged
      ->(prefix) { ->(*args) { logged_store[prefix] << args } }
    end

    it "routes protocol debug output through the configured logger" do
      transport = described_class.new("ws://127.0.0.1:9222/session", logger: logger)
      transport.send(:debug_print_send, { "id" => 1, "method" => "session.status" })
      transport.send(:debug_print_receive, { "id" => 1, "type" => "success" })

      expect(logged[Puppeteer::Bidi::Debug::BIDI_SEND].size).to eq(1)
      expect(logged[Puppeteer::Bidi::Debug::BIDI_SEND].first.first).to include("session.status")
      expect(logged[Puppeteer::Bidi::Debug::BIDI_RECEIVE].size).to eq(1)
    end

    it "falls back to warn for diagnostics when the logger disables the error channel" do
      transport = described_class.new("ws://127.0.0.1:9222/session", logger: ->(_prefix) { nil })
      expect { transport.send(:log_error, "boom") }.to output(/boom/).to_stderr
    end
  end

  describe "#url" do
    it "preserves the supplied WebSocket URL" do
      urls = [
        "ws://127.0.0.1:9222",
        "ws://127.0.0.1:9222/",
        "ws://127.0.0.1:9222/session",
        "ws://127.0.0.1:9222/session/2f9e1b1c-0f1a-4f6d-9c1e-6a1b2c3d4e5f",
        "wss://example.test?token=test-token"
      ]

      aggregate_failures do
        urls.each do |url|
          expect(described_class.new(url).url).to eq(url)
        end
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "socket"
require "openssl"
require "base64"

RSpec.describe Puppeteer::Bidi::Transport do
  # Minimal real WebSocket server over TCP. Completes the handshake, then
  # either answers ping frames or ignores them, so keepalive behavior is
  # exercised through actual peer frames instead of stubbed counters.
  class TestWebSocketServer
    WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    attr_reader :port

    def initialize(respond_to_ping: true)
      @respond_to_ping = respond_to_ping
      @mutex = Mutex.new
      @pings = 0
      @request_headers = {}
      @sockets = []
      @handler_threads = []
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
    end

    def pings
      @mutex.synchronize { @pings }
    end

    def request_headers
      @mutex.synchronize { @request_headers.dup }
    end

    def start
      @accept_thread = Thread.new do
        loop do
          socket = @server.accept
          @mutex.synchronize { @sockets << socket }
          @mutex.synchronize do
            @handler_threads << Thread.new { handle(socket) }
          end
        end
      rescue IOError, Errno::EBADF
        nil
      end
      self
    end

    def stop
      @server.close rescue nil
      @accept_thread&.join(2)
      @mutex.synchronize { @sockets.dup }.each do |socket|
        socket.close rescue nil
      end
      @mutex.synchronize { @handler_threads.dup }.each { |thread| thread.join(2) }
    end

    private

    def handle(socket)
      headers = read_handshake(socket)
      @mutex.synchronize { @request_headers = headers }
      key = headers["sec-websocket-key"]
      accept = Base64.strict_encode64(OpenSSL::Digest::SHA1.digest("#{key}#{WS_GUID}"))
      socket.write(
        "HTTP/1.1 101 Switching Protocols\r\n" \
        "Upgrade: websocket\r\n" \
        "Connection: Upgrade\r\n" \
        "Sec-WebSocket-Accept: #{accept}\r\n" \
        "\r\n"
      )
      frame_loop(socket)
    rescue EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE
      nil
    ensure
      socket.close rescue nil
    end

    def read_handshake(socket)
      buffer = +""
      buffer << socket.readpartial(4096) until buffer.include?("\r\n\r\n")
      lines = buffer.split("\r\n")
      lines.drop(1).take_while { |line| !line.empty? }.each_with_object({}) do |line, headers|
        name, value = line.split(":", 2)
        headers[name.strip.downcase] = value.strip
      end
    end

    def read_exactly(socket, count)
      buffer = +"".b
      buffer << socket.readpartial(count - buffer.bytesize) while buffer.bytesize < count
      buffer
    end

    def read_frame(socket)
      header = read_exactly(socket, 2).bytes
      opcode = header[0] & 0x0F
      masked = (header[1] & 0x80) != 0
      length = header[1] & 0x7F
      if length == 126
        length = read_exactly(socket, 2).unpack1("n")
      elsif length == 127
        length = read_exactly(socket, 8).unpack1("Q>")
      end
      mask = read_exactly(socket, 4).bytes if masked
      payload = length > 0 ? read_exactly(socket, length).bytes : []
      if mask
        payload = payload.each_with_index.map { |byte, index| byte ^ mask[index % 4] }
      end
      [opcode, payload.pack("C*")]
    end

    def write_frame(socket, opcode, payload)
      bytes = [0x80 | opcode]
      if payload.bytesize < 126
        bytes << payload.bytesize
      elsif payload.bytesize < 65_536
        bytes << 126
        bytes += [payload.bytesize].pack("n").bytes
      else
        bytes << 127
        bytes += [payload.bytesize].pack("Q>").bytes
      end
      socket.write(bytes.pack("C*") + payload)
    end

    def frame_loop(socket)
      loop do
        opcode, payload = read_frame(socket)
        case opcode
        when 0x9
          @mutex.synchronize { @pings += 1 }
          write_frame(socket, 0xA, payload) if @respond_to_ping
        when 0x8
          write_frame(socket, 0x8, "")
          break
        end
      end
    end
  end

  let(:connected_transports) { [] }
  let(:test_servers) { [] }

  # Release real connections so the suite reactor can shut down.
  after do
    connected_transports.each(&:close)
    test_servers.each(&:stop)
  end

  def start_test_server(respond_to_ping: true)
    TestWebSocketServer.new(respond_to_ping: respond_to_ping).tap do |server|
      test_servers << server
      server.start
    end
  end

  def connect_transport(transport)
    connected_transports << transport
    transport.connect
    wait_until(timeout: 5) { transport.connected? }
    transport
  end

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      Async::Task.current.sleep(0.01)
    end
  end

  def test_url(server)
    "ws://127.0.0.1:#{server.port}"
  end

  describe "ws_options headers" do
    it "passes handshake headers through, with nested headers winning over top-level headers" do
      server = start_test_server
      transport = described_class.new(
        test_url(server),
        headers: { "Authorization" => "top-level" },
        ws_options: { headers: { "Authorization" => "nested" } },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      expect(server.request_headers["authorization"]).to eq("nested")
    end

    it "uses top-level headers when nested headers are absent" do
      server = start_test_server
      transport = described_class.new(
        test_url(server),
        headers: { "Authorization" => "top-level" },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      expect(server.request_headers["authorization"]).to eq("top-level")
    end

    it "sends no custom headers by default" do
      server = start_test_server
      transport = described_class.new(test_url(server), logger: ->(_prefix) { nil })
      connect_transport(transport)

      expect(server.request_headers).not_to have_key("authorization")
    end
  end

  describe "ws_options keepalive" do
    it "closes the transport when the peer stops answering pings" do
      server = start_test_server(respond_to_ping: false)
      transport = described_class.new(
        test_url(server),
        ws_options: { keep_alive: true, keep_alive_interval_ms: 50 },
        logger: ->(_prefix) { nil }
      )
      closed = false
      transport.on_close { closed = true }
      connect_transport(transport)

      # Resolves only if the missing pong is detected; the test times out
      # otherwise, which is exactly the reported bug.
      wait_until(timeout: 5) { closed }

      expect(transport.closed?).to be(true)
      expect(server.pings).to be >= 1
    end

    it "stays open while the peer answers pings" do
      server = start_test_server(respond_to_ping: true)
      transport = described_class.new(
        test_url(server),
        ws_options: { keep_alive: true, keep_alive_interval_ms: 50 },
        logger: ->(_prefix) { nil }
      )
      connect_transport(transport)

      Async::Task.current.sleep(0.3)

      expect(transport.closed?).to be(false)
      expect(server.pings).to be >= 1
    end

    it "does not ping when keepAlive is not enabled" do
      server = start_test_server(respond_to_ping: false)
      transport = described_class.new(test_url(server), logger: ->(_prefix) { nil })
      connect_transport(transport)

      Async::Task.current.sleep(0.3)

      expect(server.pings).to eq(0)
      expect(transport.closed?).to be(false)
    end

    it "uses 30s as the default interval, matching upstream" do
      expect(described_class::DEFAULT_KEEP_ALIVE_INTERVAL_MS).to eq(30_000)
    end
  end

  describe "logger" do
    let(:logged) { Hash.new { |hash, key| hash[key] = [] } }
    let(:logger) do
      logged_store = logged
      ->(prefix) { ->(*args) { logged_store[prefix] << args } }
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

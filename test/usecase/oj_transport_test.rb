require 'test_helper'
require 'oj'

class OjTransportTest < Minitest::Test
  class FakeConnection
    def initialize(messages)
      @messages = messages
    end

    def read
      @messages.shift
    end

    def close
      # noop
    end
  end

  def test_receive_loop_parses_text_message_with_oj_mimic
    Oj.mimic_JSON
    message = Protocol::WebSocket::TextMessage.new('{"result":"ok"}')
    connection = FakeConnection.new([message])
    transport = Puppeteer::Bidi::Transport.new("ws://example.invalid")
    received = []

    transport.on_message { |data| received << data }
    transport.instance_variable_set(:@connection, connection)

    Async do
      transport.send(:receive_loop, connection)
    end.wait

    assert_equal [{"result" => "ok"}], received
  end
end

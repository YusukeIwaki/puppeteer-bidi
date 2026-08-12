# frozen_string_literal: true

# Stands in for Transport so Connection can be driven without a browser: it accepts the
# handlers Connection registers at construction, records what it was asked to send, and
# lets an example deliver a message back.
class RecordingTransport
  attr_reader :sent

  def initialize(send_error: nil)
    @sent = []
    @send_error = send_error
  end

  def on_message(&block)
    @on_message = block
  end

  def on_close(&block)
    @on_close = block
  end

  def close
    @on_close&.call
  end

  def async_send_message(message)
    raise @send_error if @send_error

    @sent << message
    Async { message }
  end

  def receive(message)
    @on_message.call(message)
  end

  def reply(id, result)
    receive({ "id" => id, "type" => "success", "result" => result })
  end
end

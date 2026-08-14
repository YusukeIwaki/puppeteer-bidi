# frozen_string_literal: true

require "json"
require "net/http"
require "socket"
require "spec_helper"
require "timeout"
require "uri"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Connecting to geckodriver" do
  def geckodriver_host
    "127.0.0.1"
  end

  def find_available_port
    server = TCPServer.new(geckodriver_host, 0)
    server.addr[1]
  ensure
    server&.close
  end

  def wait_for_geckodriver(port)
    Timeout.timeout(10) do
      loop do
        Socket.tcp(geckodriver_host, port, connect_timeout: 0.1, &:close)
        break
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
        sleep(0.1)
      end
    end
  end

  def webdriver_request(uri, request)
    Net::HTTP.start(uri.host, uri.port) do |http|
      http.open_timeout = 5
      http.read_timeout = 60
      http.request(request)
    end
  end

  def delete_session(port, session_id)
    uri = URI("http://#{geckodriver_host}:#{port}/session/#{session_id}")
    webdriver_request(uri, Net::HTTP::Delete.new(uri))
  rescue IOError, SystemCallError, Timeout::Error
    nil
  end

  def signal_process_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH
    nil
  end

  def wait_for_process(pid)
    Process.wait(pid)
  rescue Errno::ECHILD
    nil
  end

  def stop_process_group(pid)
    signal_process_group("TERM", pid)
    Timeout.timeout(5) { wait_for_process(pid) }
  rescue Timeout::Error
    signal_process_group("KILL", pid)
    wait_for_process(pid)
  end

  it "connects to the session-scoped WebDriver BiDi endpoint without rewriting it" do
    port = find_available_port
    geckodriver_pid = spawn(
      ENV.fetch("GECKODRIVER_PATH", "geckodriver"),
      "--host", geckodriver_host,
      "--port", port.to_s,
      "--log", "info",
      pgroup: true
    )

    wait_for_geckodriver(port)

    uri = URI("http://#{geckodriver_host}:#{port}/session")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = JSON.generate(
      capabilities: {
        alwaysMatch: {
          browserName: "firefox",
          webSocketUrl: true,
          "moz:firefoxOptions": {
            binary: ENV.fetch("FIREFOX_PATH"),
            args: ["-headless"]
          }
        }
      }
    )

    response = webdriver_request(uri, request)
    expect(response).to be_a(Net::HTTPSuccess), response.body

    session = JSON.parse(response.body).fetch("value")
    session_id = session.fetch("sessionId")
    ws_url = session.fetch("capabilities").fetch("webSocketUrl")

    expect(URI(ws_url).path).to eq("/session/#{session_id}")

    transport = Puppeteer::Bidi::Transport.new(ws_url)
    expect(transport.url).to eq(ws_url)

    Sync do
      Puppeteer::Bidi::AsyncUtils.async_timeout(10_000) { transport.connect }.wait
      expect(transport).to be_connected

      connection = Puppeteer::Bidi::Connection.new(transport)
      status = connection.async_send_command("session.status", {}, timeout: 10_000).wait
      expect(status).to include("ready")
    ensure
      connection ? connection.close : transport.close
    end
  ensure
    delete_session(port, session_id) if port && session_id
    stop_process_group(geckodriver_pid) if geckodriver_pid
  end
end
# rubocop:enable Metrics/BlockLength

# frozen_string_literal: true

require 'sinatra/base'
require 'webrick'
require 'socket'
require 'timeout'
require 'net/http'

module TestServer
  class App < Sinatra::Base
    set :public_folder, File.join(__dir__, '../assets')
    set :static, true

    # Disable verbose logging
    set :logging, false
    set :dump_errors, false
    set :show_exceptions, false

    # Serve static files
    get '*' do
      pass
    end
  end

  class Server
    attr_reader :port, :prefix, :cross_process_prefix, :empty_page

    def initialize
      @port = find_available_port
      @prefix = "http://localhost:#{@port}"
      @cross_process_prefix = "http://127.0.0.1:#{@port}"
      @empty_page = "#{@prefix}/empty.html"
      @server_thread = nil
    end

    def start
      @server_thread = Thread.new do
        # Suppress WEBrick logs
        App.set :bind, 'localhost'
        App.set :server, :webrick
        App.set :quiet, true

        App.run!(
          port: @port,
          server_settings: {
            Logger: WEBrick::Log.new('/dev/null'),
            AccessLog: []
          }
        )
      end

      # Wait for server to be ready
      wait_for_server
    end

    def stop
      App.quit!
      @server_thread&.kill
      @server_thread&.join(1)
    end

    private

    def find_available_port
      (4567..4577).each do |port|
        begin
          server = TCPServer.new('localhost', port)
          server.close
          return port
        rescue Errno::EADDRINUSE
          # Port is in use, try next one
        end
      end
      raise 'No available port found'
    end

    def wait_for_server
      Timeout.timeout(5) do
        loop do
          begin
            response = Net::HTTP.get_response(URI("#{@prefix}/empty.html"))
            break if response.code.to_i < 500
          rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL
            sleep 0.1
          end
        end
      end
    rescue Timeout::Error
      raise 'Test server failed to start'
    end
  end
end

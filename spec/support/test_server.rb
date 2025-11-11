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

    # Custom routes storage
    class_variable_set(:@@custom_routes, {})
    class_variable_set(:@@request_promises, {})

    # Check for custom routes before serving static files
    get '*' do
      routes = self.class.class_variable_get(:@@custom_routes)

      if routes.key?(request.path_info)
        # Notify that this request was received
        promises = self.class.class_variable_get(:@@request_promises)
        if promises.key?(request.path_info)
          promises[request.path_info].each(&:resolve)
          promises.delete(request.path_info)
        end

        handler = routes[request.path_info]

        # Create a response writer that can be controlled externally
        writer = TestServer::ResponseWriter.new

        # Call the handler with request and writer
        handler.call(request, writer)

        # Stream the response - wait for writer to finish
        stream do |out|
          writer.wait_for_finish
          out << writer.body
        end
      else
        # Serve static file
        pass
      end
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
      clear_routes
      App.quit!
      @server_thread&.kill
      @server_thread&.join(1)
    end

    # Clear all custom routes
    def clear_routes
      App.class_variable_get(:@@custom_routes).clear
      App.class_variable_get(:@@request_promises).clear
    end

    # Set a custom route handler
    # @param path [String] The path to handle (e.g., '/one-style.css')
    # @yield [request, response_writer] Block to handle the request
    #   response_writer has methods: write(data), finish, finished?
    def set_route(path, &block)
      routes = App.class_variable_get(:@@custom_routes)
      routes[path] = block
    end

    # Wait for a request to a specific path
    # @param path [String] The path to wait for
    # @param timeout [Numeric] Timeout in seconds (default: 5)
    def wait_for_request(path, timeout: 5)
      promise = RequestPromise.new

      promises = App.class_variable_get(:@@request_promises)
      promises[path] ||= []
      promises[path] << promise

      Timeout.timeout(timeout) do
        promise.wait
      end
    rescue Timeout::Error
      raise "Timeout waiting for request to #{path}"
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

  # Simple promise class for request waiting
  class RequestPromise
    def initialize
      @resolved = false
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def resolve
      @mutex.synchronize do
        @resolved = true
        @condition.broadcast
      end
    end

    def wait
      @mutex.synchronize do
        @condition.wait(@mutex) unless @resolved
      end
    end

    def resolved?
      @mutex.synchronize { @resolved }
    end
  end

  # Response writer that can be controlled externally
  class ResponseWriter
    attr_reader :body

    def initialize
      @body = ''
      @finished = false
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def write(data)
      @mutex.synchronize do
        @body << data
      end
    end

    def finish
      @mutex.synchronize do
        @finished = true
        @condition.broadcast
      end
    end

    def finished?
      @mutex.synchronize { @finished }
    end

    def wait_for_finish
      @mutex.synchronize do
        @condition.wait(@mutex) unless @finished
      end
    end
  end
end

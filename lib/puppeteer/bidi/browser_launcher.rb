# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'async'
require 'async/http/endpoint'
require 'json'
require 'net/http'

module Puppeteer
  module Bidi
    # BrowserLauncher handles launching Firefox with BiDi support
    class BrowserLauncher
      class LaunchError < Error; end

      DEFAULT_ARGS = [
        '--no-remote',
        '--foreground'
      ].freeze

      BIDI_REQUIRED_PREFS = {
        'remote.active-protocols' => 3  # Enable WebDriver BiDi (bit 0=CDP, bit 1=BiDi)
      }.freeze

      attr_reader :executable_path, :user_data_dir

      def initialize(executable_path: nil, user_data_dir: nil, headless: true, args: [])
        @executable_path = executable_path || find_firefox
        @user_data_dir = user_data_dir
        @headless = headless
        @extra_args = args
        @temp_user_data_dir = nil
        @process = nil
        @ws_endpoint = nil
      end

      # Launch Firefox and return BiDi WebSocket endpoint
      # @return [String] WebSocket endpoint URL
      def launch
        setup_user_data_dir
        port = find_available_port

        args = build_launch_args(port)

        # Launch Firefox process
        stdin, stdout, stderr, wait_thr = Open3.popen3(@executable_path, *args)
        @process = wait_thr

        # Close stdin as we don't need it
        stdin.close

        # Wait for BiDi endpoint to be available
        @ws_endpoint = wait_for_ws_endpoint(port, stdout, stderr)

        unless @ws_endpoint
          kill
          raise LaunchError, 'Failed to get BiDi WebSocket endpoint'
        end

        @ws_endpoint
      rescue => e
        kill
        raise LaunchError, "Failed to launch Firefox: #{e.message}"
      end

      # Kill the Firefox process
      def kill
        if @process && @process.alive?
          begin
            Process.kill('TERM', @process.pid)
            # Give it time to shut down gracefully
            sleep(0.5)
            Process.kill('KILL', @process.pid) if @process.alive?
          rescue Errno::ESRCH
            # Process already dead
          end
        end

        cleanup_temp_user_data_dir
      end

      # Wait for process to exit
      def wait
        @process&.value
      end

      private

      def find_firefox
        candidates = [
          ENV['FIREFOX_PATH'],
          '/usr/bin/firefox',
          '/usr/bin/firefox-devedition',
          '/usr/bin/firefox-esr',
          '/snap/bin/firefox',
          '/Applications/Firefox.app/Contents/MacOS/firefox',
          '/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox',
        ].compact

        candidates.each do |path|
          return path if File.executable?(path)
        end

        raise LaunchError, 'Could not find Firefox executable. Set FIREFOX_PATH environment variable.'
      end

      def setup_user_data_dir
        if @user_data_dir
          FileUtils.mkdir_p(@user_data_dir)
        else
          @temp_user_data_dir = Dir.mktmpdir('puppeteer-firefox-')
          @user_data_dir = @temp_user_data_dir
        end

        # Create prefs.js for BiDi support
        create_prefs_file
      end

      def create_prefs_file
        profile_dir = File.join(@user_data_dir, 'profile')
        FileUtils.mkdir_p(profile_dir)

        prefs_file = File.join(profile_dir, 'prefs.js')
        prefs_content = BIDI_REQUIRED_PREFS.map do |key, value|
          value_str = value.is_a?(String) ? "\"#{value}\"" : value
          "user_pref(\"#{key}\", #{value_str});"
        end.join("\n")

        File.write(prefs_file, prefs_content)
      end

      def cleanup_temp_user_data_dir
        if @temp_user_data_dir && Dir.exist?(@temp_user_data_dir)
          FileUtils.rm_rf(@temp_user_data_dir)
        end
      end

      def find_available_port
        # Let Firefox choose a random port by using 0
        # We'll read the actual port from the DevToolsActivePort file
        0
      end

      def build_launch_args(port)
        args = DEFAULT_ARGS.dup

        # Add headless flag if needed
        args << '--headless' if @headless

        # Add remote debugging port
        args << '--remote-debugging-port' << port.to_s

        # Add profile
        profile_dir = File.join(@user_data_dir, 'profile')
        args << '--profile' << profile_dir

        # Add user arguments
        args.concat(@extra_args)

        args
      end

      def wait_for_ws_endpoint(port, stdout, stderr, timeout: 30)
        deadline = Time.now + timeout

        # Start threads to read output
        output_lines = []
        error_lines = []
        ws_endpoint = nil
        mutex = Mutex.new

        stdout_thread = Thread.new do
          stdout.each_line do |line|
            mutex.synchronize { output_lines << line }
            # Check for WebDriver BiDi endpoint in stdout
            if line =~ /WebDriver BiDi listening on (ws:\/\/[^\s]+)/
              mutex.synchronize { ws_endpoint = $1 }
            end
          end
        rescue => e
          warn "Error reading stdout: #{e.message}"
        end

        stderr_thread = Thread.new do
          stderr.each_line do |line|
            mutex.synchronize { error_lines << line }
            # Debug: print all stderr lines to help diagnose
            puts "[Firefox stderr] #{line}" if ENV['DEBUG_FIREFOX']
            # Firefox outputs the BiDi WebSocket endpoint to stderr
            if line =~ /WebDriver BiDi listening on (ws:\/\/[^\s]+)/
              mutex.synchronize { ws_endpoint = $1 }
            end
          end
        rescue => e
          warn "Error reading stderr: #{e.message}"
        end

        # Wait for WebSocket endpoint to be detected
        loop do
          if Time.now > deadline
            stdout_thread.kill
            stderr_thread.kill
            warn "Timeout waiting for BiDi endpoint. stdout: #{output_lines.join}"
            warn "stderr: #{error_lines.join}"
            return nil
          end

          # Check if process died
          unless @process.alive?
            warn "Firefox process died. stderr: #{error_lines.join}"
            return nil
          end

          # Check if we found the endpoint
          mutex.synchronize do
            if ws_endpoint
              # Keep threads running to consume output (detach them)
              stdout_thread.join(0.1)
              stderr_thread.join(0.1)
              return ws_endpoint
            end
          end

          sleep(0.1)
        end
      ensure
        # Detach the output threads (let them run in background)
        stdout_thread&.join(1)
        stderr_thread&.join(1)
      end
    end
  end
end

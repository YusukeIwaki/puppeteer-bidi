# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::BrowserLauncher do
  describe "#launch" do
    it "adds the session path to Firefox's bare BiDi endpoint" do
      launcher = described_class.new(executable_path: "/bin/true")
      stdin = instance_double(IO, close: nil)
      stdout = instance_double(IO)
      stderr = instance_double(IO)
      process = instance_double(Thread)

      allow(launcher).to receive_messages(
        setup_user_data_dir: nil,
        find_available_port: 0,
        build_launch_args: []
      )
      allow(Open3).to receive(:popen3).with("/bin/true").and_return([stdin, stdout, stderr, process])
      allow(launcher).to receive(:wait_for_ws_endpoint)
        .with(0, stdout, stderr)
        .and_return("ws://127.0.0.1:9222")

      expect(launcher.launch).to eq("ws://127.0.0.1:9222/session")
    end
  end
end

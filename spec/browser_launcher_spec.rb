# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Puppeteer::Bidi::BrowserLauncher do
  def build_launcher(**options)
    described_class.new(executable_path: "/bin/true", **options)
  end

  describe "temporary profile cleanup" do
    it "removes the temporary profile when the executable cannot be launched" do
      launcher = described_class.new(executable_path: "/nonexistent-firefox-binary")

      expect { launcher.launch }.to raise_error(described_class::LaunchError)

      temp_dir = launcher.instance_variable_get(:@temp_user_data_dir)
      expect(temp_dir).not_to be_nil
      expect(Dir.exist?(temp_dir)).to be(false)
    end

    it "retries removal and does not mask the original error" do
      launcher = build_launcher
      launcher.send(:setup_user_data_dir)
      temp_dir = launcher.instance_variable_get(:@temp_user_data_dir)

      attempts = 0
      allow(FileUtils).to receive(:rm_r).and_wrap_original do |original, *args|
        attempts += 1
        raise Errno::EACCES, "denied" if attempts < 3

        original.call(*args)
      end

      expect { launcher.kill }.not_to raise_error
      expect(attempts).to be >= 3
      expect(Dir.exist?(temp_dir)).to be(false)
    end

    it "reports real filesystem removal failures without raising from kill" do
      skip "POSIX permission failures cannot be simulated here" if Gem.win_platform? || Process.uid == 0

      stub_const(
        "#{described_class}::REMOVE_DIR_MAX_RETRIES",
        2
      )
      logged = []
      logger = ->(_prefix) { ->(*args) { logged << args } }
      launcher = described_class.new(executable_path: "/bin/true", logger: logger)
      launcher.send(:setup_user_data_dir)
      temp_dir = launcher.instance_variable_get(:@temp_user_data_dir)

      File.chmod(0o555, temp_dir)
      begin
        expect { launcher.kill }.not_to raise_error
      ensure
        File.chmod(0o755, temp_dir)
        FileUtils.rm_rf(temp_dir)
      end

      expect(logged.flatten.join).to include("Failed to remove temporary user data dir")
    end

    it "keeps user-supplied data directories untouched" do
      Dir.mktmpdir do |dir|
        launcher = build_launcher(user_data_dir: dir)
        launcher.send(:setup_user_data_dir)

        expect { launcher.kill }.not_to raise_error
        expect(Dir.exist?(dir)).to be(true)
      end
    end
  end

  describe "default profile preferences" do
    it "disables remote-settings networking without the obsolete remote.enabled pref" do
      Dir.mktmpdir do |dir|
        launcher = build_launcher(user_data_dir: dir)
        launcher.send(:setup_user_data_dir)

        prefs = File.read(File.join(dir, "profile", "prefs.js"))

        expect(prefs).to include('user_pref("services.settings.server", "data:,#remote-settings-dummy/v1");')
        expect(prefs).not_to include("remote.enabled")
      end
    end
  end
end

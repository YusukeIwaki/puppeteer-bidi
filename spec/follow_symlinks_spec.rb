# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Puppeteer::Bidi.set_follow_symlinks" do
  around do |example|
    saved = Puppeteer::Bidi.follow_symlinks?
    example.run
    Puppeteer::Bidi.set_follow_symlinks(saved)
  end

  it "follows symlinks by default" do
    expect(Puppeteer::Bidi.follow_symlinks?).to be(true)
  end

  describe ".write_binary_file" do
    let(:tmpdir) { Dir.mktmpdir("pptr-symlink-") }

    after { FileUtils.rm_rf(tmpdir) }

    def symlink_supported?
      target = File.join(tmpdir, "target.bin")
      link = File.join(tmpdir, "link.bin")
      File.binwrite(target, "x")
      File.symlink(target, link)
      true
    rescue SystemCallError, NotImplementedError
      false
    end

    it "creates parent directories first and preserves overwrite behavior" do
      path = File.join(tmpdir, "nested", "dir", "out.bin")

      expect(Puppeteer::Bidi.write_binary_file(path, "one")).to eq(3)
      expect(Puppeteer::Bidi.write_binary_file(path, "two!")).to eq(4)
      expect(File.binread(path)).to eq("two!")
    end

    it "follows symlinks while the policy is enabled" do
      skip "symlinks not supported here" unless symlink_supported?

      target = File.join(tmpdir, "target.bin")
      link = File.join(tmpdir, "link.bin")

      Puppeteer::Bidi.write_binary_file(link, "data")
      expect(File.binread(target)).to eq("data")
    end

    it "raises ELOOP for symlinked paths while the policy is disabled" do
      skip "symlinks not supported here" unless symlink_supported?

      target = File.join(tmpdir, "target.bin")
      link = File.join(tmpdir, "link.bin")
      Puppeteer::Bidi.set_follow_symlinks(false)

      error = nil
      begin
        Puppeteer::Bidi.write_binary_file(link, "data")
      rescue SystemCallError => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.errno).to eq(Errno::ELOOP::Errno)
      expect(File.binread(target)).to eq("x")
    end

    it "still writes regular files while the policy is disabled" do
      Puppeteer::Bidi.set_follow_symlinks(false)
      path = File.join(tmpdir, "regular.bin")

      expect(Puppeteer::Bidi.write_binary_file(path, "data")).to eq(4)
      expect(File.binread(path)).to eq("data")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Puppeteer::Bidi::ScreenRecording do
  let(:video_path) { File.join(tmpdir, "recording.webm") }
  let(:tmpdir) { Dir.mktmpdir("pptr-record-") }

  after { FileUtils.rm_rf(tmpdir) }

  def stub_core_context(start_result:, stop_result: { "path" => nil })
    context = double("core_browsing_context")
    allow(context).to receive(:once)
    allow(context).to receive(:start_screencast) { |*| Async { start_result } }
    allow(context).to receive(:stop_screencast) { |*| Async { stop_result } }
    context
  end

  def stub_page(core_context)
    frame = double("frame", browsing_context: core_context)
    double("page", main_frame: frame)
  end

  let(:core_context) do
    File.binwrite(video_path, "video-bytes")
    stub_core_context(start_result: { "screencast" => "cast-1", "path" => video_path })
  end
  let(:page) { stub_page(core_context) }
  let(:options) { {} }

  subject(:recording) do
    described_class.new(page, options, ->(_prefix) { nil })
  end

  describe "#start" do
    it "registers close handling before starting" do
      recording

      expect(core_context).to have_received(:once).with(:closed)
      expect(core_context).not_to have_received(:start_screencast)
    end

    it "omits absent protocol keys" do
      recording.start

      expect(core_context).to have_received(:start_screencast).with(audio: nil, video: nil)
    end

    it "sends audio and video constraints" do
      options.merge!(audio: true, max_width: 800, max_height: 600, frame_rate: 30)
      recording.start

      expect(core_context).to have_received(:start_screencast)
        .with(audio: true, video: { width: 800, height: 600, frameRate: 30 })
    end

    it "prefers frameRate over its fps alias" do
      options.merge!(frame_rate: 30, fps: 15)
      recording.start

      expect(core_context).to have_received(:start_screencast)
        .with(audio: nil, video: { frameRate: 30 })
    end

    it "falls back to fps when frameRate is absent" do
      options.merge!(fps: 15)
      recording.start

      expect(core_context).to have_received(:start_screencast)
        .with(audio: nil, video: { frameRate: 15 })
    end
  end

  describe "#stop" do
    it "delivers the recorded bytes to piped destinations and closes them" do
      recording.start
      destination = StringIO.new
      recording.pipe(destination)

      recording.stop

      expect(recording.stopped?).to be(true)
      expect(recording.data).to eq("video-bytes")
      expect(destination.string).to eq("video-bytes")
      expect(destination.closed?).to be(true)
    end

    it "is idempotent" do
      recording.start
      recording.stop
      recording.stop

      expect(core_context).to have_received(:stop_screencast).once
    end

    it "stops without a screencast id and still closes destinations" do
      destination = StringIO.new
      recording.pipe(destination)

      recording.stop

      expect(recording.stopped?).to be(true)
      expect(core_context).not_to have_received(:stop_screencast)
      expect(destination.closed?).to be(true)
    end

    it "logs stop failures and falls back to the start path" do
      File.binwrite(video_path, "video-bytes")
      logged = []
      logger = ->(_prefix) { ->(*args) { logged << args } }
      failing = stub_core_context(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => nil, "error" => "timed out" }
      )
      recording = described_class.new(stub_page(failing), {}, logger)
      recording.start
      recording.stop

      expect(logged.flatten.join).to include("timed out")
      expect(recording.data).to eq("video-bytes")
    end
  end

  describe "Page#record" do
    let(:browser_context) { double("browser_context", logger: nil) }
    let(:recording_page) do
      Puppeteer::Bidi::Page.new(browser_context, double("page_browsing_context", closed?: false)).tap do |page_instance|
        frame = double("frame", browsing_context: core_context)
        allow(page_instance).to receive(:main_frame).and_return(frame)
      end
    end

    it "rejects non-positive dimensions and rates with the upstream errors" do
      expect { recording_page.record(max_width: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`maxWidth` must be greater than 0.")
      expect { recording_page.record(max_height: -1) }
        .to raise_error(Puppeteer::Bidi::Error, "`maxHeight` must be greater than 0.")
      expect { recording_page.record(frame_rate: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`frameRate` must be greater than 0.")
      expect { recording_page.record(fps: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`fps` must be greater than 0.")
    end

    it "stops the recording and re-raises when starting fails" do
      allow(core_context).to receive(:start_screencast).and_raise(StandardError, "no screencast")
      path = File.join(tmpdir, "nested", "out.webm")

      expect { recording_page.record(path: path) }.to raise_error(StandardError, "no screencast")
      expect(File.exist?(path)).to be(true)
    end

    it "refuses to overwrite an existing file when overwrite is false" do
      path = File.join(tmpdir, "out.webm")
      File.binwrite(path, "original")

      expect { recording_page.record(path: path, overwrite: false) }.to raise_error(Errno::EEXIST)
      expect(File.binread(path)).to eq("original")
    end

    it "rejects symlinked paths with ELOOP while following is disabled" do
      target = File.join(tmpdir, "out.webm")
      link = File.join(tmpdir, "out-link.webm")
      File.binwrite(target, "original")
      begin
        File.symlink(target, link)
      rescue SystemCallError, NotImplementedError
        skip "symlinks are not supported on this platform"
      end

      saved = Puppeteer::Bidi.follow_symlinks?
      Puppeteer::Bidi.set_follow_symlinks(false)
      begin
        expect { recording_page.record(path: link) }.to raise_error(Errno::ELOOP)
      ensure
        Puppeteer::Bidi.set_follow_symlinks(saved)
      end
    end
  end
end

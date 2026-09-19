# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Puppeteer::Bidi::ScreenRecording do
  let(:video_path) { File.join(tmpdir, "recording.webm") }
  let(:tmpdir) { Dir.mktmpdir("pptr-record-") }

  after { FileUtils.rm_rf(tmpdir) }

  # Mock core context mirroring upstream MockBrowsingContext: a command log,
  # scripted start/stop responses, and close-event emission.
  def stub_core_context(start_result:, stop_result:)
    commands = []
    context = double("core_browsing_context")
    closed_handlers = []
    allow(context).to receive(:once) do |event, &block|
      closed_handlers << block if event == :closed
    end
    allow(context).to receive(:fire_closed) { closed_handlers.each(&:call) }
    allow(context).to receive(:start_screencast) do |**kwargs|
      commands << [:start_screencast, kwargs]
      Async { start_result }
    end
    allow(context).to receive(:stop_screencast) do |screencast_id|
      commands << [:stop_screencast, screencast_id]
      Async { stop_result }
    end
    allow(context).to receive(:commands) { commands }
    context
  end

  def stub_page(core_context)
    frame = double("frame", browsing_context: core_context)
    double("page", main_frame: frame)
  end

  # Real Page going through Page#record, mirroring upstream MockBidiPage.
  def recording_page(core_context)
    browser_context = double("browser_context", logger: nil, logger_explicit: false)
    Puppeteer::Bidi::Page.new(browser_context, double("page_browsing_context", closed?: false)).tap do |page_instance|
      frame = double("frame", browsing_context: core_context)
      allow(page_instance).to receive(:main_frame).and_return(frame)
    end
  end

  # Evented writable destination with upstream WritableDestination behavior.
  class EventedDestination
    def initialize(async_finish: false)
      @handlers = Hash.new { |hash, key| hash[key] = [] }
      @written = []
      @closed = false
      @close_called = false
      @async_finish = async_finish
    end

    attr_reader :written

    def write(data)
      @written << data
    end

    def once(event, &block)
      @handlers[event] << block
      self
    end

    def fire(event)
      @handlers[event].each(&:call)
    end

    def close
      @close_called = true
      return if @async_finish

      @closed = true
      fire(:close)
    end

    def close_called?
      @close_called
    end

    def closed?
      return true if @async_finish && @finished

      @closed
    end

    def finish!
      @finished = true
      fire(:finish)
    end
  end

  # Destination finishing after a delay, mirroring Node EventEmitter timing.
  class DelayedFinishDestination < Puppeteer::Bidi::Core::EventEmitter
    def initialize(delay, event: :finish)
      super()
      @delay = delay
      @event = event
      @written = []
    end

    attr_reader :written

    def write(data)
      @written << data
      true
    end

    define_method(:end) do
      delay = @delay
      event = @event
      Async do |task|
        task.sleep(delay)
        emit(event)
      end
      nil
    end
  end

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      Async::Task.current.sleep(0.01)
    end
  end

  def stop_calls(context)
    context.commands.count { |method, _| method == :stop_screencast }
  end

  describe "upstream BidiScreenRecording cases" do
    it "should start screen recording and read file on stop" do
      File.binwrite(video_path, "video-data")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record(
        audio: true, max_width: 1920, max_height: 1080, frame_rate: 60
      )

      expect(core_context.commands[0]).to eq(
        [:start_screencast, { audio: true, video: { width: 1920, height: 1080, frameRate: 60 } }]
      )

      destination = StringIO.new
      recording.pipe(destination)
      recording.stop

      expect(destination.string).to eq("video-data")
      expect(recording.data).to eq("video-data")
      expect(core_context.commands).to include([:stop_screencast, "screencast-1"])
    end

    it "should support fps as alias for frameRate" do
      File.binwrite(video_path, "")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record(fps: 24)

      expect(core_context.commands[0]).to eq(
        [:start_screencast, { audio: nil, video: { frameRate: 24 } }]
      )

      recording.stop
    end

    it "should validate options" do
      core_context = stub_core_context(start_result: {}, stop_result: {})
      page = recording_page(core_context)

      expect { page.record(max_width: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`maxWidth` must be greater than 0.")
      expect { page.record(max_width: -10) }
        .to raise_error(Puppeteer::Bidi::Error, "`maxWidth` must be greater than 0.")
      expect { page.record(max_height: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`maxHeight` must be greater than 0.")
      expect { page.record(max_height: -10) }
        .to raise_error(Puppeteer::Bidi::Error, "`maxHeight` must be greater than 0.")
      expect { page.record(frame_rate: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`frameRate` must be greater than 0.")
      expect { page.record(frame_rate: -5) }
        .to raise_error(Puppeteer::Bidi::Error, "`frameRate` must be greater than 0.")
      expect { page.record(fps: 0) }
        .to raise_error(Puppeteer::Bidi::Error, "`fps` must be greater than 0.")
      expect { page.record(fps: -5) }
        .to raise_error(Puppeteer::Bidi::Error, "`fps` must be greater than 0.")
    end

    it "should support path returned from stopScreencast" do
      stop_path = File.join(tmpdir, "from-stop.webm")
      File.binwrite(stop_path, "hello")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-start", "path" => "" },
        stop_result: { "path" => stop_path }
      )
      recording = recording_page(core_context).record

      destination = StringIO.new
      recording.pipe(destination)
      recording.stop

      expect(destination.string).to eq("hello")
      expect(recording.data).to eq("hello")
      expect(core_context.commands).to include([:stop_screencast, "screencast-start"])
    end

    it "should support async iteration" do
      File.binwrite(video_path, "chunkA")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record

      stopper = Async { recording.stop }

      received = []
      recording.each { |chunk| received << chunk }
      stopper.wait

      expect(received.join).to eq("chunkA")
    end

    it "should stop on browsing context closed" do
      File.binwrite(video_path, "")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record

      core_context.fire_closed
      # Calling stop again should be a no-op
      recording.stop

      expect(stop_calls(core_context)).to eq(1)
    end

    it "should stop on close" do
      File.binwrite(video_path, "")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record

      recording.close

      expect(recording.stopped?).to be(true)
      expect(stop_calls(core_context)).to eq(1)
    end
  end

  describe "supplementary stream contracts" do
    def started_recording(start_result:, stop_result:)
      File.binwrite(video_path, "video-bytes")
      core_context = stub_core_context(start_result: start_result, stop_result: stop_result)
      [recording_page(core_context).record, core_context]
    end

    it "registers close handling before starting" do
      core_context = stub_core_context(start_result: {}, stop_result: {})
      described_class.new(stub_page(core_context), {}, ->(_prefix) { nil })

      expect(core_context).to have_received(:once).with(:closed)
      expect(core_context).not_to have_received(:start_screencast)
    end

    it "prefers frameRate over its fps alias" do
      core_context = stub_core_context(start_result: {}, stop_result: {})
      recording_page(core_context).record(frame_rate: 30, fps: 15)

      expect(core_context).to have_received(:start_screencast)
        .with(audio: nil, video: { frameRate: 30 })
    end

    it "keeps an iterator open until the recording stops without caller-side polling" do
      File.binwrite(video_path, "chunkA")
      core_context = stub_core_context(
        start_result: { "screencast" => "screencast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record

      received = []
      completed = false
      reader = Async do
        recording.each { |chunk| received << chunk }
        completed = true
      end
      Async::Task.current.sleep(0.02)
      returned_before_stop = completed
      recording.stop
      reader.wait

      expect([returned_before_stop, received]).to eq([false, ["chunkA"]])
    end

    it "makes concurrent stops wait for the in-flight stop" do
      recording, core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      gate = Async::Promise.new
      entered = false
      stop_count = 0
      allow(core_context).to receive(:stop_screencast) do
        entered = true
        stop_count += 1
        Async do
          gate.wait
          { "path" => video_path }
        end
      end

      first = Async { recording.stop }
      wait_until { entered }
      second_done = false
      second = Async do
        recording.stop
        second_done = true
      end
      Async::Task.current.sleep(0.05)

      expect(second_done).to be(false)

      gate.resolve(nil)
      first.wait
      second.wait

      expect(stop_count).to eq(1)
      expect(recording.data).to eq("video-bytes")
    end

    it "shares stop failures with in-flight callers while later stops succeed" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      broken = double("broken destination", write: true)
      allow(broken).to receive(:end).and_raise(StandardError, "end boom")
      recording.pipe(broken)

      errors = []
      first = Async do
        begin
          recording.stop
        rescue StandardError => error
          errors << error
        end
      end
      second = Async do
        begin
          recording.stop
        rescue StandardError => error
          errors << error
        end
      end
      first.wait
      second.wait

      expect(errors.map(&:message)).to eq(["end boom", "end boom"])
      expect { recording.stop }.not_to raise_error
      expect { recording.close }.not_to raise_error
    end

    it "lets the readable side complete while a piped destination is still finishing" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      destination = EventedDestination.new(async_finish: true)
      recording.pipe(destination)

      received = []
      reader_done = false
      reader = Async do
        recording.each { |chunk| received << chunk }
        reader_done = true
      end
      stopper = Async { recording.stop }
      Async::Task.current.sleep(0.02)
      observed = [destination.close_called?, reader_done, received.dup]
      destination.finish!
      stopper.wait
      reader.wait

      expect(observed).to eq([true, true, ["video-bytes"]])
    ensure
      stopper&.stop
      reader&.stop
    end

    it "keeps readable bytes available when a destination fails to end" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      broken = double("broken destination", write: true)
      allow(broken).to receive(:end).and_raise(StandardError, "end boom")
      recording.pipe(broken)

      expect { recording.stop }.to raise_error("end boom")

      received = []
      expect { recording.each { |chunk| received << chunk } }.not_to raise_error
      expect(received).to eq(["video-bytes"])
    end

    it "writes each destination once even when piped twice" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      destination = StringIO.new
      recording.pipe(destination)
      recording.pipe(destination)
      recording.stop

      expect(destination.string).to eq("video-bytes")
    end

    it "removes destinations that error before the bytes arrive" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      destination = EventedDestination.new
      recording.pipe(destination)
      destination.fire(:error)
      recording.stop

      expect(destination.written).to be_empty
      expect(recording.data).to eq("video-bytes")
    end

    it "waits for evented destinations to finish closing" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      destination = EventedDestination.new(async_finish: true)
      recording.pipe(destination)

      stopper = Async { recording.stop }
      wait_until { destination.close_called? }
      destination.finish!
      stopper.wait

      expect(destination.written).to eq(["video-bytes"])
    end

    it "completes when a destination errors while closing" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      destination = EventedDestination.new(async_finish: true)
      recording.pipe(destination)

      stopper = Async { recording.stop }
      wait_until { destination.close_called? }
      destination.fire(:error)
      stopper.wait

      expect(destination.written).to eq(["video-bytes"])
    end

    it "recognizes an already finished writable destination without waiting for another finish event" do
      File.binwrite(video_path, "chunkA")
      core_context = stub_core_context(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record
      destination = double("finished destination", write: true, end: nil, writableFinished: true, closed?: false)
      allow(destination).to receive(:once)
      recording.pipe(destination)

      finished = false
      stopper = Async do
        recording.stop
        finished = true
      end
      Async::Task.current.sleep(0.02)

      expect(finished).to be(true)
    ensure
      stopper&.stop
    end

    it "registers completion listeners for all destinations before waiting for the first" do
      File.binwrite(video_path, "chunkA")
      core_context = stub_core_context(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      recording = recording_page(core_context).record
      recording.pipe(DelayedFinishDestination.new(0.05))
      recording.pipe(DelayedFinishDestination.new(0.01))

      finished = false
      stopper = Async do
        recording.stop
        finished = true
      end
      Async::Task.current.sleep(0.1)

      expect(finished).to be(true)
    ensure
      stopper&.stop
    end

    it "stops without a screencast id and still closes destinations" do
      core_context = stub_core_context(start_result: {}, stop_result: {})
      recording = described_class.new(stub_page(core_context), {}, ->(_prefix) { nil })
      destination = StringIO.new
      recording.pipe(destination)

      recording.stop

      expect(recording.stopped?).to be(true)
      expect(core_context).not_to have_received(:stop_screencast)
      expect(destination.closed?).to be(true)
    end

    it "logs stop failures and falls back to the start path" do
      logged = []
      logger = ->(_prefix) { ->(*args) { logged << args } }
      core_context = stub_core_context(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => nil, "error" => "timed out" }
      )
      File.binwrite(video_path, "video-bytes")
      recording = described_class.new(stub_page(core_context), {}, logger)
      recording.start
      recording.stop

      expect(logged.flatten.join).to include("timed out")
      expect(recording.data).to eq("video-bytes")
    end
  end

  describe "Page#record file handling" do
    def file_recording_page(start_result:, stop_result: {})
      core_context = stub_core_context(start_result: start_result, stop_result: stop_result)
      recording_page(core_context)
    end

    it "stops the recording and re-raises when starting fails" do
      page = file_recording_page(start_result: {}, stop_result: {})
      core_context = page.main_frame.browsing_context
      allow(core_context).to receive(:start_screencast).and_raise(StandardError, "no screencast")
      path = File.join(tmpdir, "nested", "out.webm")

      expect { page.record(path: path) }.to raise_error(StandardError, "no screencast")
      expect(File.exist?(path)).to be(true)
    end

    it "refuses to overwrite an existing file when overwrite is false" do
      page = file_recording_page(start_result: {}, stop_result: {})
      path = File.join(tmpdir, "out.webm")
      File.binwrite(path, "original")

      expect { page.record(path: path, overwrite: false) }.to raise_error(Errno::EEXIST)
      expect(File.binread(path)).to eq("original")
    end

    it "rejects symlinked paths with ELOOP while following is disabled" do
      page = file_recording_page(start_result: {}, stop_result: {})
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
        expect { page.record(path: link) }.to raise_error(Errno::ELOOP)
      ensure
        Puppeteer::Bidi.set_follow_symlinks(saved)
      end
    end
  end
end

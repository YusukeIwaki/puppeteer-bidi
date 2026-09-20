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

    # Real evented core context with scripted screencast responses, for
    # closed-dispatch ordering tests that need multiple listeners.
    def evented_context(path:, gate: nil, stop_counts: nil)
      context = Puppeteer::Bidi::Core::EventEmitter.new
      context.define_singleton_method(:start_screencast) do |**_|
        Async { { "screencast" => "cast-1", "path" => path } }
      end
      context.define_singleton_method(:stop_screencast) do |*_|
        stop_counts << :stop if stop_counts
        Async do
          gate&.wait
          { "path" => path }
        end
      end
      context
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

    it "rejects only the first caller when overlapping stops fail to end a destination" do
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
      broken = double("broken destination", write: true)
      allow(broken).to receive(:end).and_raise(StandardError, "end boom")
      recording.pipe(broken)

      outcomes = []
      first = Async do
        begin
          recording.stop
          outcomes << [:first, :fulfilled]
        rescue StandardError => error
          outcomes << [:first, error.message]
        end
      end
      wait_until { entered }
      second = Async do
        begin
          recording.stop
          outcomes << [:second, :fulfilled]
        rescue StandardError => error
          outcomes << [:second, error.message]
        end
      end
      Async::Task.current.sleep(0.05)

      # The queued caller waits for the in-flight stop; it cannot complete
      # while the gate is unresolved.
      expect(outcomes).to be_empty

      gate.resolve(nil)
      first.wait
      second.wait

      # Upstream `@guarded` serializes callers via a mutex: the queued caller
      # re-runs the body, observes `stopped`, and succeeds instead of
      # inheriting the first caller's failure.
      expect(outcomes).to eq([[:first, "end boom"], [:second, :fulfilled]])
      expect(stop_count).to eq(1)
      expect { recording.stop }.not_to raise_error
      expect { recording.close }.not_to raise_error
    end

    it "closes destinations and the readable side when the error logger raises" do
      missing_path = File.join(tmpdir, "missing.webm")
      logger = ->(_prefix) { ->(_error) { raise "logger boom" } }
      core_context = stub_core_context(
        start_result: { "screencast" => "cast-1", "path" => "" },
        stop_result: { "path" => missing_path }
      )
      gate = Async::Promise.new
      entered = false
      allow(core_context).to receive(:stop_screencast) do
        entered = true
        Async do
          gate.wait
          { "path" => missing_path }
        end
      end
      recording = described_class.new(stub_page(core_context), {}, logger)
      recording.start
      destination = StringIO.new
      recording.pipe(destination)

      outcomes = []
      first = Async do
        begin
          recording.stop
          outcomes << [:first, :fulfilled]
        rescue StandardError => error
          outcomes << [:first, error.message]
        end
      end
      wait_until { entered }
      second = Async do
        begin
          recording.stop
          outcomes << [:second, :fulfilled]
        rescue StandardError => error
          outcomes << [:second, error.message]
        end
      end
      gate.resolve(nil)
      first.wait
      second.wait

      # Upstream `finally { await closeDestinations() }`: the first caller's
      # logger failure still propagates, queued and later callers succeed,
      # and cleanup always runs.
      expect(outcomes).to eq([[:first, "logger boom"], [:second, :fulfilled]])
      expect(destination.closed?).to be(true)
      expect { recording.stop }.not_to raise_error
      expect { recording.close }.not_to raise_error

      received = []
      reader_done = false
      reader = Async do
        recording.each { |chunk| received << chunk }
        reader_done = true
      end
      Async::Task.current.sleep(0.02)
      expect([reader_done, received]).to eq([true, []])
    ensure
      reader&.stop
    end

    it "releases stop coordination when the in-flight stop is cancelled" do
      recording, core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      gate = Async::Promise.new
      entered = false
      allow(core_context).to receive(:stop_screencast) do
        entered = true
        Async do
          gate.wait
          { "path" => video_path }
        end
      end

      owner_outcome = nil
      owner = Async do
        begin
          recording.stop
          owner_outcome = :fulfilled
        rescue Async::Stop
          owner_outcome = :stopped
        end
      end
      wait_until { entered }
      owner.stop
      owner.wait
      # Release the stubbed protocol task so the reactor can finish.
      gate.resolve(nil)

      later_done = false
      later = Async do
        recording.stop
        later_done = true
      end
      later.wait

      expect([owner_outcome, later_done, recording.stopped?]).to eq([:stopped, true, true])
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

    it "completes closed dispatch while the automatic protocol stop stays gated" do
      File.binwrite(video_path, "video-bytes")
      gate = Async::Promise.new
      stop_counts = []
      core_context = evented_context(path: video_path, gate: gate, stop_counts: stop_counts)
      recording = recording_page(core_context).record
      later_called = false
      core_context.on(:closed) { later_called = true }

      emitter = Async { core_context.emit(:closed) }
      # Dispatch must finish while the gate stays closed: nested Async may
      # need a scheduler tick before the emitter resumes, so wait with a
      # bounded deadline instead of reading the flag immediately.
      observed = begin
        Async::Task.current.with_timeout(2) { emitter.wait }
        later_called
      rescue Async::TimeoutError
        false
      end
      gate.resolve(nil)
      emitter.wait
      recording.stop

      expect(observed).to be(true)
      expect(stop_counts.size).to eq(1)
      expect(recording.data).to eq("video-bytes")
    ensure
      gate&.resolve(nil) unless gate&.resolved?
      emitter&.stop
    end

    it "completes closed dispatch while the automatic stop waits for a destination" do
      File.binwrite(video_path, "video-bytes")
      stop_counts = []
      core_context = evented_context(path: video_path, stop_counts: stop_counts)
      recording = recording_page(core_context).record
      destination = EventedDestination.new(async_finish: true)
      recording.pipe(destination)
      later_called = false
      core_context.on(:closed) { later_called = true }

      emitter = Async { core_context.emit(:closed) }
      observed = begin
        Async::Task.current.with_timeout(2) { emitter.wait }
        later_called
      rescue Async::TimeoutError
        false
      end
      # The destination can only finish after dispatch already completed.
      wait_until { destination.close_called? }
      destination.finish!
      emitter.wait
      recording.stop

      expect(observed).to be(true)
      expect(destination.written).to eq(["video-bytes"])
      expect(stop_counts.size).to eq(1)
    ensure
      destination&.finish!
      emitter&.stop
    end

    it "logs automatic stop failures without failing closed dispatch" do
      File.binwrite(video_path, "video-bytes")
      logged = []
      logger = ->(_prefix) { ->(*args) { logged << args } }
      stop_counts = []
      core_context = evented_context(path: video_path, stop_counts: stop_counts)
      recording = described_class.new(stub_page(core_context), {}, logger)
      recording.start
      broken = double("broken destination", write: true)
      allow(broken).to receive(:end).and_raise(StandardError, "end boom")
      recording.pipe(broken)
      later_called = false
      core_context.on(:closed) { later_called = true }

      emitter = Async { core_context.emit(:closed) }
      observed = begin
        Async::Task.current.with_timeout(2) { emitter.wait }
        later_called
      rescue Async::TimeoutError
        false
      end
      wait_until(timeout: 2) { logged.any? }

      expect(observed).to be(true)
      expect(logged.flatten.join).to include("end boom")
      expect { recording.stop }.not_to raise_error
      expect(stop_counts.size).to eq(1)
    ensure
      emitter&.stop
    end

    it "skips ending a destination unpiped by an earlier end callback" do
      core_context = Puppeteer::Bidi::Core::EventEmitter.new
      recording = described_class.new(stub_page(core_context), {}, ->(_prefix) { nil })
      calls = []
      first = Puppeteer::Bidi::Core::EventEmitter.new
      second = Puppeteer::Bidi::Core::EventEmitter.new
      first.define_singleton_method(:end) { calls << :first; second.emit(:unpipe); emit(:finish) }
      second.define_singleton_method(:end) { calls << :second; emit(:finish) }
      recording.pipe(first)
      recording.pipe(second)
      recording.stop

      expect(calls).to eq([:first])
    end

    it "writes to a destination piped by an earlier write callback" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      calls = []
      first = Puppeteer::Bidi::Core::EventEmitter.new
      second = Puppeteer::Bidi::Core::EventEmitter.new
      first.define_singleton_method(:write) do |bytes|
        calls << [:first, bytes]
        recording.pipe(second)
        true
      end
      second.define_singleton_method(:write) { |bytes| calls << [:second, bytes]; true }
      first.define_singleton_method(:end) { emit(:finish) }
      second.define_singleton_method(:end) { emit(:finish) }
      recording.pipe(first)
      recording.stop

      expect(calls).to eq([[:first, "video-bytes"], [:second, "video-bytes"]])
    end

    it "ends a destination piped by an earlier end callback" do
      core_context = Puppeteer::Bidi::Core::EventEmitter.new
      recording = described_class.new(stub_page(core_context), {}, ->(_prefix) { nil })
      calls = []
      first = Puppeteer::Bidi::Core::EventEmitter.new
      second = Puppeteer::Bidi::Core::EventEmitter.new
      first.define_singleton_method(:end) { calls << :first; recording.pipe(second); emit(:finish) }
      second.define_singleton_method(:end) { calls << :second; emit(:finish) }
      recording.pipe(first)
      Async::Task.current.with_timeout(2) { recording.stop }

      expect(calls).to eq([:first, :second])
    end

    it "revisits a destination deleted and re-piped during writing at the end of insertion order" do
      recording, _core_context = started_recording(
        start_result: { "screencast" => "cast-1", "path" => video_path },
        stop_result: { "path" => video_path }
      )
      calls = []
      first = Puppeteer::Bidi::Core::EventEmitter.new
      second = Puppeteer::Bidi::Core::EventEmitter.new
      first.define_singleton_method(:write) do |bytes|
        calls << [:first, bytes]
        if calls.count { |entry| entry.first == :first } == 1
          emit(:unpipe)
          recording.pipe(self)
        end
        true
      end
      second.define_singleton_method(:write) { |bytes| calls << [:second, bytes]; true }
      first.define_singleton_method(:end) { emit(:finish) }
      second.define_singleton_method(:end) { emit(:finish) }
      recording.pipe(first)
      recording.pipe(second)
      recording.stop

      expect(calls).to eq([[:first, "video-bytes"], [:second, "video-bytes"], [:first, "video-bytes"]])
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

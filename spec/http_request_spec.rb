# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::HTTPRequest do
  let(:logged) { Hash.new { |hash, key| hash[key] = [] } }
  let(:logger) do
    logged_store = logged
    ->(prefix) { ->(*args) { logged_store[prefix] << args } }
  end

  def fake_core_request(id: "req-1")
    request = double("core_request", id: id, blocked?: false)
    allow(request).to receive(:on)
    allow(request).to receive(:once)
    request
  end

  def fake_frame
    page = double("page")
    allow(page).to receive(:emit)
    frame = double("frame")
    allow(frame).to receive(:page).and_return(page)
    frame
  end

  describe ".handle_interception_error" do
    it "reports through the retained logger instead of reaching through the frame" do
      error = StandardError.new("NETWORK_ERROR")

      expect {
        described_class.handle_interception_error(error, logger)
      }.not_to output.to_stderr

      entries = logged[Puppeteer::Bidi::Debug::ERROR]
      expect(entries.size).to eq(1)
      expect(entries.first.first).to include("NETWORK_ERROR")
    end

    it "re-raises validation errors even when a logger is retained" do
      error = StandardError.new("Invalid header name")

      expect {
        described_class.handle_interception_error(error, logger)
      }.to raise_error(error)
      expect(logged).to be_empty
    end

    it "preserves the env-gated warn fallback without a logger" do
      error = StandardError.new("NETWORK_ERROR")

      expect {
        described_class.handle_interception_error(error)
      }.not_to output.to_stderr
    end
  end

  describe ".from" do
    it "retains the logger and propagates it to redirect requests" do
      redirect_handlers = {}
      core_request = fake_core_request
      allow(core_request).to receive(:on) do |event, &block|
        redirect_handlers[event] = block if event == :redirect
      end

      request = described_class.from(core_request, fake_frame, false, logger: logger)

      expect(request.instance_variable_get(:@logger)).to be(logger)

      redirected = fake_core_request(id: "req-2")
      redirect_handlers[:redirect].call(redirected)

      chain = request.redirect_chain
      expect(chain).to eq([request])
      follow_up = described_class.for_core_request(redirected)
      expect(follow_up.instance_variable_get(:@logger)).to be(logger)
    end
  end
end

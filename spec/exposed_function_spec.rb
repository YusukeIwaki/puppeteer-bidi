# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::ExposedFunction do
  def build_function(logger: nil, logger_explicit: false)
    factory = logger || ->(_prefix) { nil }
    function = described_class.allocate
    function.instance_variable_set(:@logger, factory)
    function.instance_variable_set(:@logger_explicit, logger_explicit)
    function.instance_variable_set(:@debug_error, factory.call(Puppeteer::Bidi::Debug::ERROR))
    function
  end

  describe "#debug_error" do
    it "reports through the error logger" do
      logged = []
      function = build_function(logger: ->(_prefix) { ->(*args) { logged << args } })

      function.send(:debug_error, StandardError.new("boom"))

      expect(logged.flatten.first).to be_a(StandardError)
    end

    it "stays silent with an explicitly disabled logger" do
      function = build_function(logger_explicit: true)

      expect { function.send(:debug_error, StandardError.new("boom")) }.not_to output.to_stderr
    end

    it "preserves the env-gated warn fallback without an explicit logger" do
      function = build_function
      ENV["DEBUG_BIDI_COMMAND"] = "1"
      begin
        expect { function.send(:debug_error, StandardError.new("boom")) }
          .to output(/boom/).to_stderr
      ensure
        ENV.delete("DEBUG_BIDI_COMMAND")
      end
    end
  end
end

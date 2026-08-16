# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Core::EventEmitter do
  subject(:emitter) { described_class.new }

  let(:listener) { proc { |_event| } }

  it "returns itself from #on, #once, and #off" do
    expect(emitter.on(:event, &listener)).to equal(emitter)
    expect(emitter.once(:event, &listener)).to equal(emitter)
    expect(emitter.off(:event, &listener)).to equal(emitter)
  end

  it "returns itself when disposed" do
    emitter.dispose

    expect(emitter.on(:event, &listener)).to equal(emitter)
    expect(emitter.once(:event, &listener)).to equal(emitter)
    expect(emitter.off(:event, &listener)).to equal(emitter)
  end
end

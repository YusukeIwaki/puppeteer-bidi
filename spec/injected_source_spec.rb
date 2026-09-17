# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Puppeteer injected source" do
  subject(:source) { Puppeteer::Bidi::PUPPETEER_INJECTED_SOURCE }

  it "is generated from puppeteer-core 25.10.0" do
    header = File.read(File.join(__dir__, "..", "lib", "puppeteer", "bidi", "injected_source.rb"))

    expect(header).to include("puppeteer-core@25.10.0")
  end

  it "provides the MutationPoller lifecycle" do
    expect(source).to include("MutationObserver")
    expect(source).to include("Polling never started")
    expect(source).to include("Polling stopped")
  end

  it "observes open shadow roots recursively for mutation polling" do
    # Upstream Poller.ts observes the root plus every reachable open shadow
    # root and picks up shadow trees added after waiting begins. Markers of
    # the minified implementation below.
    expect(source).to include("shadowRoot")
    expect(source).to include("addedNodes")
    expect(source).to include("createTreeWalker")
  end
end

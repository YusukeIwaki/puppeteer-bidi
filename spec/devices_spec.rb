# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::KnownDevices do
  subject(:devices) { Puppeteer::Bidi::KnownDevices }

  it "covers the current iPhone lineup in portrait and landscape" do
    expect(devices.keys).to contain_exactly(
      "iPhone SE (3rd gen)", "iPhone SE (3rd gen) landscape",
      "iPhone 16", "iPhone 16 landscape",
      "iPhone 16 Plus", "iPhone 16 Plus landscape",
      "iPhone 16 Pro", "iPhone 16 Pro landscape",
      "iPhone 16 Pro Max", "iPhone 16 Pro Max landscape",
      "iPhone 16e", "iPhone 16e landscape",
      "iPhone 17", "iPhone 17 landscape",
      "iPhone Air", "iPhone Air landscape",
      "iPhone 17 Pro", "iPhone 17 Pro landscape",
      "iPhone 17 Pro Max", "iPhone 17 Pro Max landscape",
      "iPhone 17e", "iPhone 17e landscape",
      "iPhone 6", "iPhone 13", "iPad Pro landscape"
    )
  end

  it "matches the upstream descriptors" do
    pro_max = devices["iPhone 17 Pro Max"]
    expect(pro_max[:user_agent]).to include("iPhone")
    expect(pro_max[:viewport]).to eq(
      {
        width: 440,
        height: 763,
        device_scale_factor: 3,
        is_mobile: true,
        has_touch: true,
        is_landscape: false,
      }
    )

    air_landscape = devices["iPhone Air landscape"]
    expect(air_landscape[:viewport]).to include(width: 794, height: 370, is_landscape: true)

    iphone_6 = devices["iPhone 6"]
    expect(iphone_6[:user_agent]).to include("iPhone OS 11_0")
    expect(iphone_6[:viewport]).to include(width: 375, height: 667, is_landscape: false)

    iphone_13 = devices["iPhone 13"]
    expect(iphone_13[:user_agent]).to include("iPhone OS 15_0")
    expect(iphone_13[:viewport]).to include(width: 390, height: 844, is_landscape: false)

    ipad_pro_landscape = devices["iPad Pro landscape"]
    expect(ipad_pro_landscape[:user_agent]).to include("iPad")
    expect(ipad_pro_landscape[:viewport]).to include(width: 1366, height: 1024, is_landscape: true)
  end

  describe "Page#emulate" do
    let(:page) do
      Puppeteer::Bidi::Page.new(
        double("browser_context", logger: nil, logger_explicit: false),
        double("core_browsing_context", closed?: false)
      )
    end

    it "composes set_user_agent and set_viewport from the descriptor" do
      allow(page).to receive(:set_user_agent)
      allow(page).to receive(:set_viewport)

      page.emulate(devices["iPhone 17 Pro"])

      expect(page).to have_received(:set_user_agent).with(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1"
      )
      expect(page).to have_received(:set_viewport).with(
        width: 402,
        height: 681,
        device_scale_factor: 3,
        has_touch: true,
        is_mobile: true,
        is_landscape: false
      )
    end
  end
end

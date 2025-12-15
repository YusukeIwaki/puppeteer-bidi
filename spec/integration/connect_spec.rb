# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Puppeteer::Bidi.connect", type: :integration do
  it "should be able to reconnect" do
    with_browser do |browser|
      ws_endpoint = browser.ws_endpoint
      page = browser.new_page
      page.goto($shared_test_server.empty_page)
      browser.disconnect

      Puppeteer::Bidi.connect(ws_endpoint) do |reconnected|
        page2 = reconnected.new_page
        expect(page2.evaluate('7 * 8')).to eq(56)
        expect(browser.pages.count).to eq(0)
        expect(reconnected.pages.count).to eq(2)
      end

      browser.wait_for_exit
    end
  end
end

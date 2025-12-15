# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Puppeteer::Bidi.connect", type: :integration do
  it "should be able to reconnect" do
    browser = Puppeteer::Bidi.launch_browser_instance(headless: headless_mode?)

    begin
      ws_endpoint = browser.ws_endpoint
      browser.disconnect

      reconnected = Puppeteer::Bidi.connect(ws_endpoint)
      begin
        page = reconnected.new_page
        page.goto("data:text/html,<title>ok</title>")
        expect(page.title).to eq("ok")
      ensure
        reconnected.close
      end

      browser.wait_for_exit
    ensure
      browser.close
    end
  end
end


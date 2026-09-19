# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Page.record', type: :integration do
  it 'should record page' do
    with_test_state do |page:, **|
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'recording.webm')

        begin
          recording = page.record(path: path)
        rescue Puppeteer::Bidi::Connection::ProtocolError => error
          # Upstream expects Page.record to fail until the browser implements
          # browsingContext.startScreencast (Firefox: https://bugzilla.mozilla.org/show_bug.cgi?id=2066782,
          # Chrome: supported from 153). Recheck when the test browser supports screencasts.
          # See TestExpectations at puppeteer-core-v25.10.0 ("[page.test] Page Page.record *").
          pending "Screen recording is not supported by this browser: #{error.message}"
          raise error
        end

        page.goto('data:text/html,<input>')
        input = page.wait_for_selector('input')
        input.type('ab', delay: 100)

        recording.stop

        expect(File.size(path)).to be > 0
      end
    end
  end
end

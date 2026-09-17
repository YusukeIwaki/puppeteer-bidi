# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Page.record', type: :integration do
  it 'should record page' do
    # Pending: Firefox does not support the WebDriver BiDi screencast
    # commands yet. See https://bugzilla.mozilla.org/show_bug.cgi?id=2066782.
    pending 'browsingContext.startScreencast not supported by Firefox yet'

    with_test_state do |page:, **|
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'recording.webm')

        recording = page.record(path: path)

        page.goto('data:text/html,<input>')
        input = page.wait_for_selector('input')
        input.type('ab', delay: 100)

        recording.stop

        expect(File.size(path)).to be > 0
      end
    end
  end
end

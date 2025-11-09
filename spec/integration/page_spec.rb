# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Page' do
  describe 'Page.url' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        expect(page.url).to eq('about:blank')
        page.goto(server.empty_page, wait_until: 'load')
        expect(page.url).to eq(server.empty_page)
      end
    end
  end

  describe 'Page.setJavaScriptEnabled' do
    it 'should work' do
      # Pending: Firefox does not yet support emulation.setScriptingEnabled BiDi command
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      with_test_state do |page:, **|
        page.set_javascript_enabled(false)
        expect(page.javascript_enabled?).to be false

        page.goto('data:text/html, <script>var something = "forbidden"</script>')

        error = nil
        begin
          page.evaluate('something')
        rescue => e
          error = e
        end

        expect(error).not_to be_nil
        expect(error.message).to include('something is not defined')

        page.set_javascript_enabled(true)
        expect(page.javascript_enabled?).to be true

        page.goto('data:text/html, <script>var something = "forbidden"</script>')
        result = page.evaluate('something')
        expect(result).to eq('forbidden')
      end
    end

    it 'setInterval should pause' do
      # Pending: Firefox does not yet support emulation.setScriptingEnabled BiDi command
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      with_test_state do |page:, **|
        # Set up an interval that increments a counter every 0ms
        page.evaluate(<<~JS)
          () => {
            setInterval(() => {
              globalThis.intervalCounter = (globalThis.intervalCounter ?? 0) + 1;
            }, 0);
          }
        JS

        # Disable JavaScript execution on the page
        page.set_javascript_enabled(false)

        # Capture the current value of the counter after JS is disabled
        interval_counter = page.evaluate('globalThis.intervalCounter')

        # Wait a bit to ensure the interval would have fired if JS was still enabled
        sleep 0.1

        # Re-enable JavaScript
        page.set_javascript_enabled(true)

        # Check that the counter didn't increment while JS was disabled
        new_counter = page.evaluate('globalThis.intervalCounter')

        # The counter should not have changed (or changed very little due to timing)
        expect(new_counter).to be <= (interval_counter + 2)
      end
    end
  end
end

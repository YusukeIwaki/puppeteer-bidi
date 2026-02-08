# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Browser' do
  describe 'Browser.get_window_bounds / Browser.set_window_bounds' do
    it 'should get and set window bounds for a window page' do
      with_test_state do |browser:, context:, **|
        page = nil
        begin
          initial_bounds = { left: 10, top: 20, width: 800, height: 600 }
          page = context.new_page(type: 'window', window_bounds: initial_bounds)

          window_id = page.window_id
          expect(window_id).to be_a(String)
          expect(window_id).not_to be_empty

          current_bounds = browser.get_window_bounds(window_id)
          expect(current_bounds.keys).to include(:left, :top, :width, :height, :window_state)

          browser.set_window_bounds(window_id, { window_state: 'maximized' })
          expect(browser.get_window_bounds(window_id)[:window_state]).to eq('maximized')

          updated_bounds = { left: 100, top: 120, width: 900, height: 700, window_state: 'normal' }
          expect {
            browser.set_window_bounds(window_id, updated_bounds)
          }.not_to raise_error
        rescue Puppeteer::Bidi::Connection::ProtocolError => error
          pending "Window management is not supported by this browser: #{error.message}"
          raise error
        ensure
          page&.close unless page&.closed?
        end
      end
    end
  end
end

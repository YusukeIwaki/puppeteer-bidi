# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Browser' do
  describe 'Browser.get_window_bounds / Browser.set_window_bounds' do
    it 'should get and set window bounds for a window page' do
      with_test_state do |browser:, context:, **|
        page = nil
        begin
          page = context.new_page(type: 'window')

          window_id = page.window_id
          expect(window_id).to be_a(String)
          expect(window_id).not_to be_empty

          initial_bounds = { left: 10, top: 20, width: 800, height: 600 }
          browser.set_window_bounds(window_id, initial_bounds)
          expect(browser.get_window_bounds(window_id)).to include(initial_bounds)

          updated_bounds = { left: 100, top: 200, width: 1600, height: 1200 }
          browser.set_window_bounds(window_id, updated_bounds)
          expect(browser.get_window_bounds(window_id)).to include(updated_bounds)

          browser.set_window_bounds(window_id, { window_state: 'maximized' })
          expect(browser.get_window_bounds(window_id)[:window_state]).to eq('maximized')
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

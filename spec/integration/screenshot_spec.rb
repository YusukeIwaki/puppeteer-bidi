# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Screenshot', type: :integration do
  describe 'Page.screenshot' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-sanity.png')).to be true
      end
    end

    it 'should clip rect' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot(
          clip: {
            x: 50,
            y: 100,
            width: 150,
            height: 100
          }
        )

        expect(compare_with_golden(screenshot, 'screenshot-clip-rect.png')).to be true
      end
    end

    it 'should get screenshot bigger than the viewport' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 50, height: 50)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot(
          clip: {
            x: 25,
            y: 25,
            width: 100,
            height: 100
          }
        )

        expect(compare_with_golden(screenshot, 'screenshot-offscreen-clip.png')).to be true
      end
    end

    it 'should clip clip bigger than the viewport without "captureBeyondViewport"' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 50, height: 50)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot(
          capture_beyond_viewport: false,
          clip: {
            x: 25,
            y: 25,
            width: 100,
            height: 100
          }
        )

        expect(compare_with_golden(screenshot, 'screenshot-offscreen-clip-2.png')).to be true
      end
    end

    it 'should run in parallel' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")

        # Take 3 screenshots in parallel using threads
        threads = (0...3).map do |i|
          Thread.new do
            page.screenshot(
              clip: {
                x: 50 * i,
                y: 0,
                width: 50,
                height: 50
              }
            )
          end
        end

        screenshots = threads.map(&:value)

        expect(compare_with_golden(screenshots[1], 'grid-cell-1.png')).to be true
      end
    end

    it 'should take fullPage screenshots' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot(full_page: true)

        expect(compare_with_golden(screenshot, 'screenshot-grid-fullpage.png')).to be true
      end
    end

    it 'should take fullPage screenshots without captureBeyondViewport' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot(
          full_page: true,
          capture_beyond_viewport: false
        )

        expect(compare_with_golden(screenshot, 'screenshot-grid-fullpage-2.png')).to be true
        expect(page.viewport).to eq({ width: 500, height: 500 })
      end
    end

    it 'should run in parallel in multiple pages' do
      with_test_state do |page:, server:, context:, **|
        n = 2
        pages = (0...n).map do
          new_page = context.new_page
          new_page.goto("#{server.prefix}/grid.html")
          new_page
        end

        # Take screenshots in parallel using threads
        threads = (0...n).map do |i|
          Thread.new do
            pages[i].screenshot(
              clip: {
                x: 50 * i,
                y: 0,
                width: 50,
                height: 50
              }
            )
          end
        end

        screenshots = threads.map(&:value)

        # Verify each screenshot
        (0...n).each do |i|
          expect(compare_with_golden(screenshots[i], "grid-cell-#{i}.png")).to be true
        end

        # Close all pages
        pages.each(&:close)
      end
    end

    it 'should work with odd clip size on Retina displays' do
      with_test_state do |page:, **|
        # Make sure documentElement height is at least 11px
        page.set_content('<div style="width: 11px; height: 11px;"></div>')

        screenshot = page.screenshot(
          clip: {
            x: 0,
            y: 0,
            width: 11,
            height: 11
          }
        )

        expect(compare_with_golden(screenshot, 'screenshot-clip-odd-size.png')).to be true
      end
    end

    it 'should return base64' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot

        # Ruby's screenshot method already returns base64 by default
        expect(compare_with_golden(screenshot, 'screenshot-sanity.png')).to be true
      end
    end

    it 'should take fullPage screenshots when defaultViewport is null' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/grid.html")
        screenshot = page.screenshot(full_page: true)

        # Screenshot should be a base64 string
        expect(screenshot).to be_a(String)
        expect(screenshot.length).to be > 0
      end
    end

    it 'should restore to original viewport size after taking fullPage screenshots when defaultViewport is null' do
      with_test_state do |page:, server:, **|
        original_size = page.evaluate('({ width: window.innerWidth, height: window.innerHeight })')

        page.goto("#{server.prefix}/scrollbar.html")
        page.screenshot(
          full_page: true,
          capture_beyond_viewport: false
        )

        size = page.evaluate('({ width: window.innerWidth, height: window.innerHeight })')

        # Viewport should be restored to original size
        expect(size['width']).to eq(original_size['width'])
        expect(size['height']).to eq(original_size['height'])
      end
    end
  end
end

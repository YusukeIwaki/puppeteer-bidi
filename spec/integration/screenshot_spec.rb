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

  describe 'ElementHandle.screenshot' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        # Use the same selector as Puppeteer's test
        element = page.query_selector('.box:nth-of-type(3)')

        screenshot = element.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-element-bounding-box.png')).to be true
      end
    end

    it 'should take into account padding and border' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          something above
          <style>
            div {
              border: 2px solid blue;
              background: green;
              width: 50px;
              height: 50px;
            }
          </style>
          <div></div>
        HTML
        element = page.query_selector('div')

        screenshot = element.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-element-padding-border.png')).to be true
      end
    end

    it 'should capture full element when larger than viewport' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          something above
          <style>
            :root { scrollbar-width: none; }
            div.to-screenshot {
              border: 1px solid blue;
              width: 600px;
              height: 600px;
              margin-left: 50px;
            }
          </style>
          <div class="to-screenshot"></div>
        HTML
        element = page.query_selector('div.to-screenshot')

        screenshot = element.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-element-larger-than-viewport.png')).to be true

        # Verify inner dimensions are unchanged
        viewport = page.evaluate('({ width: window.innerWidth, height: window.innerHeight })')
        expect(viewport['width']).to eq(500)
        expect(viewport['height']).to eq(500)
      end
    end

    it 'should scroll element into view' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          something above
          <style>
            div.above {
              border: 2px solid blue;
              background: red;
              height: 1500px;
            }
            div.to-screenshot {
              border: 2px solid blue;
              background: green;
              width: 50px;
              height: 50px;
            }
          </style>
          <div class="above"></div>
          <div class="to-screenshot"></div>
        HTML
        element = page.query_selector('div.to-screenshot')

        screenshot = element.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-element-scrolled-into-view.png')).to be true
      end
    end

    it 'should work with a rotated element' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          <style>
            body { height: 1000px; margin: 0; }
          </style>
          <div style="position:absolute; top: 100px; left: 100px; width: 100px; height: 100px; background: green; transform: rotateZ(200deg);">&nbsp;</div>
        HTML
        element = page.query_selector('div')

        screenshot = element.screenshot

        # Use max_diff_pixels tolerance for rendering differences across Firefox versions
        # Anti-aliasing on rotated edges causes ~800 pixel differences
        expect(compare_with_golden(screenshot, 'screenshot-element-rotate.png', max_diff_pixels: 1000)).to be true
      end
    end

    it 'should fail if element has 0 height' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content('<div style="width: 50px; height: 0;"></div>')
        element = page.query_selector('div')

        expect { element.screenshot }.to raise_error('Node has 0 height.')
      end
    end

    it 'should fail if element has 0 width' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content('<div style="width: 0; height: 50px;"></div>')
        element = page.query_selector('div')

        expect { element.screenshot }.to raise_error('Node has 0 width.')
      end
    end

    # between Firefox versions. The screenshot functionality works correctly,
    # but pixel-perfect comparison fails due to subpixel rendering differences.
    it 'should work for an element with fractional dimensions' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content('<div style="width:48.51px;height:19.8px;border:1px solid black;"></div>')
        element = page.query_selector('div')

        screenshot = element.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-element-fractional.png')).to be true
      end
    end

    it 'should work for an element with an offset' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          <style>
            body { height: 1000px; margin: 0; }
          </style>
          <div style="position:absolute; top: 10.3px; left: 20.4px; width:50.3px;height:20.2px;border:1px solid black;"></div>
        HTML
        element = page.query_selector('div')

        screenshot = element.screenshot

        expect(compare_with_golden(screenshot, 'screenshot-element-fractional-offset.png')).to be true
      end
    end

    it 'should work with element clip' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          something above
          <style>
            div {
              border: 2px solid blue;
              background: green;
              width: 50px;
              height: 50px;
            }
          </style>
          <div></div>
        HTML
        element = page.query_selector('div')

        screenshot = element.screenshot(clip: { x: 10, y: 10, width: 20, height: 20 })

        expect(compare_with_golden(screenshot, 'screenshot-element-clip.png')).to be true
      end
    end
  end
end

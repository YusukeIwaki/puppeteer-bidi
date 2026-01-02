require 'test_helper'
require 'tmpdir'
require 'chunky_png'

class ExampleGithubScreenshotTest < Minitest::Test
  def test_take_screenshot_using_block
    Puppeteer::Bidi.launch(headless: true) do |browser|
      page = browser.new_page
      page.goto('https://github.com/YusukeIwaki')

      Dir.mktmpdir do |dir|
        screenshot_path = File.join(dir, 'screenshot.png')
        page.screenshot(path: screenshot_path)

        png = ChunkyPNG::Image.from_file(screenshot_path)
        assert png.width > 0
        assert png.height > 0
      end
    end
  end

  def test_take_screenshot_using_instance
    browser = Puppeteer::Bidi.launch_browser_instance(headless: true)

    # works even outside of Sync block and separate thread!
    thread = Thread.new do
      begin
        page = browser.new_page
        page.goto('https://github.com/YusukeIwaki')
        Dir.mktmpdir do |dir|
          screenshot_path = File.join(dir, 'screenshot.png')
          page.screenshot(path: screenshot_path)

          png = ChunkyPNG::Image.from_file(screenshot_path)
          assert png.width > 0
          assert png.height > 0
        end
      ensure
        browser.close
      end
    end

    thread.join
  end

  def test_use_browser_from_another_thread
    @browsers = []
    @mutex = Mutex.new

    thread = Thread.new do
      @mutex.synchronize do
        @browsers << Puppeteer::Bidi.launch_browser_instance(headless: true)
      end
    end

    thread.join
    browser = @mutex.synchronize { @browsers.pop }

    # works even outside of Sync block and separate thread!
    begin
      page = browser.new_page
      page.goto('https://github.com/YusukeIwaki')
      Dir.mktmpdir do |dir|
        screenshot_path = File.join(dir, 'screenshot.png')
        page.screenshot(path: screenshot_path)

        png = ChunkyPNG::Image.from_file(screenshot_path)
        assert png.width > 0
        assert png.height > 0
      end
    ensure
      browser.close
    end
  end
end

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'Screenshot example' do
  example 'take a screenshot of github.com/YusukeIwaki' do
    with_browser do |browser|
      page = browser.new_page
      page.goto('https://github.com/YusukeIwaki')

      Dir.mktmpdir do |dir|
        screenshot_path = File.join(dir, 'screenshot.png')
        page.screenshot(path: screenshot_path)

        # Verify screenshot was created
        expect(File.exist?(screenshot_path)).to be true
        expect(File.size(screenshot_path)).to be > 0
      end
    end
  end
end

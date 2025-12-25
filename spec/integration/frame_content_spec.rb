# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Frame.content' do
  describe '#content' do
    it 'should return the full HTML contents of the frame' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div class="hello">Hello, World!</div>')

        content = page.main_frame.content
        expect(content).to include('<div class="hello">Hello, World!</div>')
      end
    end

    it 'should include the DOCTYPE' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<!DOCTYPE html><html><head></head><body>Test</body></html>')

        content = page.main_frame.content
        expect(content).to include('<!DOCTYPE html>')
      end
    end

    it 'should work with nested HTML structure' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content(<<~HTML)
          <!DOCTYPE html>
          <html>
            <head><title>Test Page</title></head>
            <body>
              <div id="container">
                <p class="paragraph">Hello</p>
                <span>World</span>
              </div>
            </body>
          </html>
        HTML

        content = page.main_frame.content
        expect(content).to include('<title>Test Page</title>')
        expect(content).to include('<div id="container">')
        expect(content).to include('<p class="paragraph">Hello</p>')
      end
    end

    it 'should work for iframes' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/nested-frames.html")

        # Get the first child frame
        child_frame = page.main_frame.child_frames.first
        expect(child_frame).not_to be_nil

        content = child_frame.content
        expect(content).to include('<html')
        expect(content).to include('</html>')
      end
    end

    it 'should throw for detached frames' do
      with_test_state do |page:, server:, **|
        # Helper method to attach an iframe
        handle = page.evaluate_handle(<<~JS, 'frame1', server.empty_page)
          async (frameId, url) => {
            const frame = document.createElement('iframe');
            frame.src = url;
            frame.id = frameId;
            document.body.appendChild(frame);
            await new Promise(x => frame.onload = x);
            return frame;
          }
        JS
        frame1 = handle.as_element.content_frame

        # Detach the frame
        page.evaluate(<<~JS, 'frame1')
          (frameId) => {
            const frame = document.getElementById(frameId);
            frame.remove();
          }
        JS

        expect {
          frame1.content
        }.to raise_error(Puppeteer::Bidi::FrameDetachedError, /Attempted to use detached Frame/)
      end
    end

    it 'should return empty-ish content for blank page' do
      with_test_state do |page:, server:, **|
        page.goto('about:blank')

        content = page.main_frame.content
        # about:blank should still have html structure
        expect(content).to include('<html')
        expect(content).to include('<body')
      end
    end
  end
end

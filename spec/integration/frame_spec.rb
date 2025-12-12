# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Frame specs' do
  # Helper method to attach an iframe to the page
  def attach_frame(page, frame_id, url)
    handle = page.evaluate_handle(<<~JS, frame_id, url)
      async (frameId, url) => {
        const frame = document.createElement('iframe');
        frame.src = url;
        frame.id = frameId;
        document.body.appendChild(frame);
        await new Promise(x => frame.onload = x);
        return frame;
      }
    JS
    handle.as_element.content_frame
  end

  # Helper method to detach an iframe from the page
  def detach_frame(page, frame_id)
    page.evaluate(<<~JS, frame_id)
      (frameId) => {
        const frame = document.getElementById(frameId);
        frame.remove();
      }
    JS
  end

  # Helper method to navigate a frame
  def navigate_frame(page, frame_id, url)
    page.evaluate(<<~JS, frame_id, url)
      (frameId, url) => {
        const frame = document.getElementById(frameId);
        frame.src = url;
        return new Promise(x => frame.onload = x);
      }
    JS
  end

  # Helper method to dump frame tree structure
  # Following Puppeteer's dumpFrames implementation from test/src/utils.ts
  def dump_frames(frame, indentation = '')
    result = []
    # Replace port number with placeholder
    url = frame.url.gsub(/:\d+\//, ':<PORT>/')
    description = url

    # Get frame name from frameElement, following Puppeteer's pattern
    element = frame.frame_element
    if element
      name_or_id = element.evaluate('frame => frame.name || frame.id')
      description += " (#{name_or_id})" if name_or_id && !name_or_id.empty?
      element.dispose
    end

    result << "#{indentation}#{description}"

    frame.child_frames.each do |child|
      result.concat(dump_frames(child, "#{indentation}    "))
    end
    result
  end

  describe 'Frame.evaluateHandle' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        main_frame = page.main_frame
        window_handle = main_frame.evaluate_handle('() => window')
        expect(window_handle).to be_a(Puppeteer::Bidi::JSHandle)
      end
    end
  end

  describe 'Frame.evaluate' do
    it 'should throw for detached frames' do
      with_test_state do |page:, server:, **|
        frame1 = attach_frame(page, 'frame1', server.empty_page)
        detach_frame(page, 'frame1')

        expect {
          frame1.evaluate('() => 7 * 8')
        }.to raise_error(Puppeteer::Bidi::FrameDetachedError, /Attempted to use detached Frame/)
      end
    end

    it 'allows readonly array to be an argument' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        main_frame = page.main_frame

        # This test checks if Frame.evaluate allows a readonly array to be an argument.
        readonly_array = %w[a b c].freeze
        result = main_frame.evaluate('arr => arr', readonly_array)
        expect(result).to eq(%w[a b c])
      end
    end
  end

  describe 'Frame.page' do
    it 'should retrieve the page from a frame' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        main_frame = page.main_frame
        expect(main_frame.page).to eq(page)
      end
    end
  end

  describe 'Frame Management' do
    it 'should handle nested frames' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/nested-frames.html")
        expect(dump_frames(page.main_frame)).to eq([
          'http://localhost:<PORT>/frames/nested-frames.html',
          '    http://localhost:<PORT>/frames/two-frames.html (2frames)',
          '        http://localhost:<PORT>/frames/frame.html (uno)',
          '        http://localhost:<PORT>/frames/frame.html (dos)',
          '    http://localhost:<PORT>/frames/frame.html (aframe)'
        ])
      end
    end

    it 'should send events when frames are manipulated dynamically' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        # Set up all event listeners before any frame operations
        attached_frames = []
        navigated_frames = []
        detached_frames = []
        page.on(:frameattached) { |frame| attached_frames << frame }
        page.on(:framenavigated) { |frame| navigated_frames << frame }
        page.on(:framedetached) { |frame| detached_frames << frame }

        # Test frameattached
        attach_frame(page, 'frame1', "#{server.prefix}/frames/frame.html")
        expect(attached_frames.length).to eq(1)
        expect(attached_frames[0].url).to include('/frames/frame.html')

        # Test framenavigated (clear to only count new events)
        initial_navigated_count = navigated_frames.length
        navigate_frame(page, 'frame1', server.empty_page)
        expect(navigated_frames.length - initial_navigated_count).to eq(1)
        expect(navigated_frames.last.url).to eq(server.empty_page)

        # Test framedetached
        detach_frame(page, 'frame1')
        expect(detached_frames.length).to eq(1)
        expect(detached_frames[0].detached?).to be true
      end
    end

    it 'should send "framenavigated" when navigating on anchor URLs' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        navigated = false
        page.on(:framenavigated) { navigated = true }
        page.goto("#{server.empty_page}#foo")

        expect(navigated).to be true
        expect(page.url).to eq("#{server.empty_page}#foo")
      end
    end

    it 'should persist mainFrame on cross-process navigation' do
      with_test_state do |page:, server:, **|
        skip 'Cross-process navigation not yet implemented'

        page.goto(server.empty_page)
        main_frame = page.main_frame
        page.goto("#{server.cross_process_prefix}/empty.html")
        expect(page.main_frame).to eq(main_frame)
      end
    end

    it 'should not send attach/detach events for main frame' do
      with_test_state do |page:, server:, **|
        has_events = false
        page.on(:frameattached) { has_events = true }
        page.on(:framedetached) { has_events = true }
        page.goto(server.empty_page)
        expect(has_events).to be false
      end
    end

    it 'should detach child frames on navigation' do
      with_test_state do |page:, server:, **|
        attached_frames = []
        detached_frames = []
        navigated_frames = []
        page.on(:frameattached) { |frame| attached_frames << frame }
        page.on(:framedetached) { |frame| detached_frames << frame }
        page.on(:framenavigated) { |frame| navigated_frames << frame }
        page.goto("#{server.prefix}/frames/nested-frames.html")

        expect(attached_frames.length).to eq(4)
        expect(detached_frames.length).to eq(0)
        expect(navigated_frames.length).to eq(5)

        attached_frames.clear
        detached_frames.clear
        navigated_frames.clear
        page.goto(server.empty_page)
        expect(attached_frames.length).to eq(0)
        expect(detached_frames.length).to eq(4)
        expect(navigated_frames.length).to eq(1)
      end
    end

    it 'should support framesets' do
      with_test_state do |page:, server:, **|
        skip 'Framesets not yet implemented'

        attached_frames = []
        detached_frames = []
        navigated_frames = []
        page.on('frameattached') { |frame| attached_frames << frame }
        page.on('framedetached') { |frame| detached_frames << frame }
        page.on('framenavigated') { |frame| navigated_frames << frame }
        page.goto("#{server.prefix}/frames/frameset.html")
        expect(attached_frames.length).to eq(4)
        expect(detached_frames.length).to eq(0)
        expect(navigated_frames.length).to eq(5)

        attached_frames.clear
        detached_frames.clear
        navigated_frames.clear
        page.goto(server.empty_page)
        expect(attached_frames.length).to eq(0)
        expect(detached_frames.length).to eq(4)
        expect(navigated_frames.length).to eq(1)
      end
    end

    it 'should click elements in a frameset' do
      with_test_state do |page:, server:, **|
        skip 'Frameset click not yet implemented'

        page.goto("#{server.prefix}/frames/frameset.html")
        frame = page.wait_for_frame { |f| f.url.end_with?('/frames/frame.html') }
        div = frame.wait_for_selector('div')
        expect(div).to be_truthy
        div.click
      end
    end

    it 'should report frame from inside shadow DOM' do
      with_test_state do |page:, server:, **|
        skip 'Shadow DOM frames not yet implemented'

        page.goto("#{server.prefix}/shadow.html")
        page.evaluate(<<~JS, server.empty_page)
          async (url) => {
            const frame = document.createElement('iframe');
            frame.src = url;
            document.body.shadowRoot.appendChild(frame);
            await new Promise(x => frame.onload = x);
          }
        JS
        expect(page.frames.length).to eq(2)
        expect(page.frames[1].url).to eq(server.empty_page)
      end
    end

    it 'should report frame.parent()' do
      with_test_state do |page:, server:, **|
        attach_frame(page, 'frame1', server.empty_page)
        attach_frame(page, 'frame2', server.empty_page)
        expect(page.frames[0].parent_frame).to be_nil
        expect(page.frames[1].parent_frame).to eq(page.main_frame)
        expect(page.frames[2].parent_frame).to eq(page.main_frame)
      end
    end

    it 'should report different frame instance when frame re-attaches' do
      with_test_state do |page:, server:, **|
        skip 'Frame re-attachment not yet implemented'

        frame1 = attach_frame(page, 'frame1', server.empty_page)
        page.evaluate(<<~JS)
          () => {
            globalThis.frame = document.querySelector('#frame1');
            globalThis.frame.remove();
          }
        JS
        expect(frame1.detached?).to be true

        frame_attached_promise = Promise.new { |resolve| page.once('frameattached') { |f| resolve.call(f) } }
        page.evaluate('() => document.body.appendChild(globalThis.frame)')
        frame2 = frame_attached_promise.value

        expect(frame2.detached?).to be false
        expect(frame1).not_to eq(frame2)
      end
    end

    it 'should support url fragment' do
      with_test_state do |page:, server:, **|
        skip 'URL fragment in frames not yet implemented'

        page.goto("#{server.prefix}/frames/one-frame-url-fragment.html")

        expect(page.frames.length).to eq(2)
        expect(page.frames[1].url).to eq("#{server.prefix}/frames/frame.html?param=value#fragment")
      end
    end

    it 'should support lazy frames' do
      with_test_state do |page:, server:, **|
        skip 'Lazy frames not yet implemented'

        page.set_viewport(width: 1000, height: 1000)
        page.goto("#{server.prefix}/frames/lazy-frame.html")

        expect(page.frames.map(&:_has_started_loading)).to eq([true, true, false])
      end
    end
  end

  describe 'Frame.client' do
    it 'should return the client instance' do
      skip 'Frame.client is CDP-specific, not applicable to WebDriver BiDi'
    end
  end

  describe 'Frame.frameElement' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        attach_frame(page, 'theFrameId', server.empty_page)
        page.evaluate(<<~JS, server.empty_page)
          (url) => {
            const frame = document.createElement('iframe');
            frame.name = 'theFrameName';
            frame.src = url;
            document.body.appendChild(frame);
            return new Promise(x => frame.onload = x);
          }
        JS

        frame0 = page.frames[0].frame_element
        expect(frame0).to be_nil

        frame1 = page.frames[1].frame_element
        expect(frame1).to be_truthy
        name1 = frame1.evaluate('frame => frame.id')
        expect(name1).to eq('theFrameId')

        frame2 = page.frames[2].frame_element
        expect(frame2).to be_truthy
        name2 = frame2.evaluate('frame => frame.name')
        expect(name2).to eq('theFrameName')
      end
    end

    it 'should handle shadow roots', pending: 'BiDi protocol limitation: no DOM.getFrameOwner equivalent for shadow roots' do
      with_test_state do |page:, **|
        page.set_content(<<~HTML)
          <div id="shadow-host"></div>
          <script>
            const host = document.getElementById('shadow-host');
            const shadowRoot = host.attachShadow({mode: 'closed'});
            const frame = document.createElement('iframe');
            frame.srcdoc = '<p>Inside frame</p>';
            shadowRoot.appendChild(frame);
          </script>
        HTML

        frame = page.frames[1]
        frame_element = frame.frame_element
        tag_name = frame_element.evaluate('el => el.tagName.toLocaleLowerCase()')
        expect(tag_name).to eq('iframe')
      end
    end

    it 'should return ElementHandle in the correct world' do
      with_test_state do |page:, server:, **|
        skip 'Frame.frameElement world isolation not yet implemented'

        attach_frame(page, 'theFrameId', server.empty_page)
        page.evaluate('() => { globalThis.isMainWorld = true; }')
        expect(page.frames.length).to eq(2)

        frame1 = page.frames[1].frame_element
        expect(frame1).to be_truthy
        is_main_world = frame1.evaluate('() => globalThis.isMainWorld')
        expect(is_main_world).to be true
      end
    end
  end
end

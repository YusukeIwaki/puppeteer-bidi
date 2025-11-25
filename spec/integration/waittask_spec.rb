# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Frame.waitForFunction', type: :integration do
  it 'should accept a string' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        watchdog = Async do
          page.wait_for_function("() => window.__FOO === 1")
        end
        page.evaluate("() => window.__FOO = 1")
        watchdog.wait
      end
    end
  end

  it 'should accept a string with block' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.wait_for_function("() => window.__FOO === 1") do
        page.evaluate("() => window.__FOO = 1")
      end
    end
  end

  it 'should work when resolved right before execution context disposal' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.wait_for_function(<<~JS)
        () => {
          if (!window.__RELOADED) {
            window.__RELOADED = true;
            window.location.reload();
            return false;
          }
          return true;
        }
      JS
    end
  end

  it 'should poll on interval' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        start_time = Time.now

        watchdog = Async do
          page.wait_for_function("() => window.__FOO === 'hit'", polling: 200)
        end
        Async do
          page.evaluate("() => setTimeout(() => { window.__FOO = 'hit' }, 50)")
        end

        watchdog.wait
        elapsed = ((Time.now - start_time) * 1000).to_i

        expect(elapsed).to be >= 150
      end
    end
  end

  it 'should poll on interval with block' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      start_time = Time.now

      page.wait_for_function("() => window.__FOO === 'hit'", polling: 200) do
        page.evaluate("() => setTimeout(() => { window.__FOO = 'hit' }, 50)")
      end

      elapsed = ((Time.now - start_time) * 1000).to_i

      expect(elapsed).to be >= 150
    end
  end

  it 'should poll on mutation' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        success = false

        watchdog = Async do
          page.wait_for_function(
            "() => window.__FOO === 'hit'",
            polling: 'mutation'
          ).tap { success = true }
        end

        page.evaluate("() => window.__FOO = 'hit'")
        expect(success).to be false

        page.evaluate("() => document.body.appendChild(document.createElement('div'))")

        watchdog.wait
        expect(success).to be true
      end
    end
  end

  it 'should poll on mutation async' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        success = false

        watchdog = Async do
          page.wait_for_function(
            "async () => window.__FOO === 'hit'",
            polling: 'mutation'
          ).tap { success = true }
        end

        page.evaluate("async () => window.__FOO = 'hit'")
        expect(success).to be false

        page.evaluate("async () => document.body.appendChild(document.createElement('div'))")

        handle = watchdog.wait
        expect(success).to be true
        handle.dispose
      end
    end
  end

  it 'should poll on raf' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        watchdog = Async do
          page.wait_for_function("async () => window.__FOO === 'hit'", polling: 'raf')
        end
        page.evaluate("async () => window.__FOO = 'hit'")

        watchdog.wait
      end
    end
  end

  it 'should poll on raf async' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        watchdog = Async do
          page.wait_for_function("async () => window.__FOO === 'hit'", polling: 'raf')
        end

        page.evaluate("() => window.__FOO = 'hit'")

        handle = watchdog.wait
        expect(handle).not_to be_nil
        handle.dispose
      end
    end
  end

  # Known limitation: BiDi protocol's script.evaluate is blocked by CSP when using new Function()
  # Puppeteer marks this as FAIL for Firefox+BiDi in TestExpectations.json
  # See: https://github.com/puppeteer/puppeteer/blob/main/test/TestExpectations.json
  # Firefox Bug: https://bugzilla.mozilla.org/show_bug.cgi?id=1650112
  it 'should work with strict CSP policy', pending: 'BiDi script.evaluate blocked by CSP (new Function())' do
    with_test_state do |page:, server:, **|
      server.set_route('/csp.html') do |_req, res|
        res.status = 200
        res.add_header('Content-Security-Policy', "script-src #{server.prefix}")
        res.write('<html></html>')
        res.finish
      end

      page.goto("#{server.prefix}/csp.html")

      watchdog = Async do
        page.wait_for_function("() => window.__FOO === 'hit'", polling: 'raf')
      end
      page.evaluate("() => window.__FOO = 'hit'")

      watchdog.wait
    end
  end

  it 'should throw on negative polling interval' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      expect {
        page.wait_for_function("() => true", polling: -10)
      }.to raise_error(/Cannot poll with non-positive interval/)
    end
  end

  it 'should return the success value as a JSHandle' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      result = page.wait_for_function("() => 5")
      expect(result.json_value).to eq(5)
      result.dispose
    end
  end

  it 'should return the window as a success value' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      result = page.wait_for_function("() => window")
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should accept ElementHandle arguments' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.set_content('<div></div>')

      div = page.query_selector('div')

      Sync do
        resolved = false

        watchdog = Async do
          page.wait_for_function(
            "element => element.localName === 'div' && !element.parentElement",
            {},
            div
          ).tap { resolved = true }
        end

        expect(resolved).to be false

        page.evaluate('element => element.remove()', div)

        handle = watchdog.wait
        expect(resolved).to be true
        handle.dispose
      end

      div.dispose
    end
  end

  it 'should respect timeout' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      expect {
        page.wait_for_function("() => false", timeout: 10)
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /10ms exceeded/)
    end
  end

  it 'should respect default timeout' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.set_default_timeout(10)

      expect {
        page.wait_for_function("() => false")
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /10ms exceeded/)
    end
  end

  it 'should disable timeout when set to 0' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      Sync do
        watchdog = Async do
          page.wait_for_function(
            <<~JS,
              () => {
                window.__counter = (window.__counter || 0) + 1;
                return window.__injected;
              }
            JS
            timeout: 0,
            polling: 10
          )
        end

        page.wait_for_function("() => window.__counter > 10")
        page.evaluate("() => window.__injected = true")

        watchdog.wait
      end
    end
  end

  it 'should survive cross-process navigation' do
    with_test_state do |page:, server:, **|
      Sync do
        foo_found = false

        watchdog = Async do
          page.wait_for_function("() => window.__FOO === 1").tap { foo_found = true }
        end

        page.goto(server.empty_page)
        expect(foo_found).to be false

        # page.reload
        page.goto(server.empty_page)
        expect(foo_found).to be false

        page.goto("#{server.cross_process_prefix}/grid.html")
        expect(foo_found).to be false

        page.evaluate("() => window.__FOO = 1")

        watchdog.wait
        expect(foo_found).to be true
      end
    end
  end

  it 'should survive navigations' do
    with_test_state do |page:, server:, **|
      Sync do
        done = false

        watchdog = Async do
          page.wait_for_function("() => window.__DONE === true").tap { done = true }
        end

        page.goto(server.empty_page)
        expect(done).to be false

        page.goto("#{server.prefix}/grid.html")
        expect(done).to be false

        page.evaluate("() => window.__DONE = true")

        watchdog.wait
        expect(done).to be true
      end
    end
  end

  it 'should be cancellable with an abort signal' do
    skip 'Requires JS-specific AbortController/signal support.'
  end

  it 'should not cause an unhandled error when aborted' do
    skip 'Requires JS-specific AbortController/signal support.'
  end

  it 'can start multiple tasks without warnings when aborted' do
    skip 'Requires JS-specific AbortController/signal support.'
  end
end

RSpec.describe 'Frame.waitForSelector', type: :integration do
  let(:add_element) do
    <<~JAVASCRIPT
      (tag) => {
        return document.body.appendChild(document.createElement(tag));
      }
    JAVASCRIPT
  end

  def attach_frame(page, frame_id, url)
    page.evaluate(<<~JS, frame_id, url)
      async (frameId, src) => {
        const frame = document.createElement('iframe');
        frame.id = frameId;
        frame.src = src;
        document.body.appendChild(frame);
        await new Promise(resolve => (frame.onload = resolve));
      }
    JS

    # Newly attached frame should be the last entry
    page.frames.last
  end

  def detach_frame(page, frame_id)
    page.evaluate(<<~JS, frame_id)
      (frameId) => {
        const frame = document.getElementById(frameId);
        if (frame) {
          frame.remove();
        }
      }
    JS
  end

  it 'should immediately resolve promise if node exists' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      frame = page.main_frame

      element = frame.wait_for_selector('*') do
        page.evaluate(add_element, 'div')
      end

      expect(element).to be_a(Puppeteer::Bidi::ElementHandle)

      element = page.wait_for_selector('div')
      expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
    end
  end

  it 'should be cancellable' do
    skip 'AbortController/signal support needed for cancellation, which is JS-specific.'
  end

  it 'should work with removed MutationObserver' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.evaluate('() => { delete window.MutationObserver; }')

      handle = page.wait_for_selector('.zombo') do
        page.set_content('<div class="zombo">anything</div>')
      end

      text = page.evaluate('(element) => element.textContent', handle)

      expect(text).to eq('anything')
      handle.dispose
    end
  end

  it 'should resolve promise when node is added' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      frame = page.main_frame

      element = frame.wait_for_selector('div') do
        frame.evaluate(add_element, 'br')
        frame.evaluate(add_element, 'div')
      end

      tag_name = page.evaluate('(element) => element.tagName', element)
      expect(tag_name).to eq('DIV')
      element.dispose
    end
  end

  it 'should work when node is added through innerHTML' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      element = page.wait_for_selector('h3 div') do
        page.evaluate(add_element, 'span')
        page.evaluate(<<~JS)
          () => {
            const span = document.querySelector('span');
            span.innerHTML = '<h3><div></div></h3>';
          }
        JS
      end

      expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
      element.dispose
    end
  end

  it 'should work when node is added in a shadow root' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      resolved = false

      watcher = Async do
        page.wait_for_selector('div >>> h1').tap { resolved = true }
      end

      page.evaluate(add_element, 'div')

      sleep(0.04)
      expect(resolved).to eq(false)

      page.evaluate(<<~JS)
        () => {
          const host = document.querySelector('div');
          const shadow = host.attachShadow({ mode: 'open' });
          const h1 = document.createElement('h1');
          h1.textContent = 'inside';
          shadow.appendChild(h1);
        }
      JS

      handle = watcher.wait

      text = handle.evaluate('(element) => element.textContent')
      expect(text).to eq('inside')
      handle.dispose
    end
  end

  it 'should work for selector with a pseudo class' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      handle = page.wait_for_selector('input:focus') do
        page.set_content('<input></input>')
        page.click('input')
      end

      expect(handle).to be_a(Puppeteer::Bidi::ElementHandle)
      handle.dispose
    end
  end

  it 'Page.waitForSelector is shortcut for main frame' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      other_frame = attach_frame(page, 'frame1', server.empty_page)
      expect(other_frame).not_to be_nil

      main_frame = page.main_frame
      resolved_frame = nil

      Sync do
        watcher = Async do
          page.wait_for_selector('div').tap { |element| resolved_frame = element.frame }
        end

        other_frame.evaluate(add_element, 'div')
        page.evaluate(add_element, 'div')

        element = watcher.wait
        expect(resolved_frame).to eq(main_frame)
        element.dispose
      end
    end
  end

  it 'should run in specified frame' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      attach_frame(page, 'frame1', server.empty_page)
      frame2 = attach_frame(page, 'frame2', server.empty_page)
      frame1 = page.frames[1]

      expect(frame1).not_to be_nil
      expect(frame2).not_to be_nil

      resolved_frame = nil

      Sync do
        watcher = Async do
          frame2.wait_for_selector('div').tap { |element| resolved_frame = element&.frame }
        end

        frame1.evaluate(add_element, 'div')
        frame2.evaluate(add_element, 'div')

        element = watcher.wait
        expect(resolved_frame).to eq(frame2)
        element.dispose
      end
    end
  end

  it 'should throw when frame is detached' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      frame = attach_frame(page, 'frame1', server.empty_page)

      wait_error = nil

      Sync do
        watcher = Async do
          frame.wait_for_selector('.box')
        rescue => error
          wait_error = error
          nil
        end

        detach_frame(page, 'frame1')
        watcher.wait
      end

      expect(wait_error).not_to be_nil
      message = wait_error.message
      expect(message.include?('Waiting for selector `.box` failed') || message.include?('Frame detached')).to be true
    end
  end

  it 'should survive cross-process navigation' do
    with_test_state do |page:, server:, **|
      box_found = false

      Sync do
        watcher = Async do
          page.wait_for_selector('.box').tap { box_found = true }
        end

        page.goto(server.empty_page)
        expect(box_found).to be false

        page.goto(server.empty_page)
        expect(box_found).to be false

        page.goto("#{server.cross_process_prefix}/grid.html")

        watcher.wait
      end

      expect(box_found).to be true
    end
  end

  it 'should wait for element to be visible (display)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', visible: true).tap { promise_resolved = true }
        end

        page.set_content('<div style="display: none">text</div>')

        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.removeProperty("display")')

        handle = promise.wait
        expect(handle).to be_truthy
        handle.dispose if handle
        element.dispose
      end
    end
  end

  it 'should wait for element to be visible without DOM mutations' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', visible: true).tap { promise_resolved = true }
        end

        page.set_content(<<~HTML)
          <style>
            div { display: none; }
          </style>
          <div>text</div>
        HTML

        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')
        expect(element).not_to be_nil

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        page.evaluate(<<~JS)
          () => {
            const sheet = new CSSStyleSheet();
            sheet.replaceSync('div { display: block; }');
            document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
          }
        JS

        handle = promise.wait
        expect(handle).to be_truthy
        handle.dispose if handle
        element.dispose
      end
    end
  end

  it 'should wait for element to be visible (visibility)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', visible: true).tap { promise_resolved = true }
        end

        page.set_content('<div style="visibility: hidden">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.setProperty("visibility", "collapse")')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.removeProperty("visibility")')

        handle = promise.wait
        expect(handle).to be_truthy
        handle.dispose if handle
        element.dispose
      end
    end
  end

  it 'should wait for element to be visible (bounding box)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', visible: true).tap { promise_resolved = true }
        end

        page.set_content('<div style="width: 0">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => { element.style.setProperty("height", "0"); element.style.removeProperty("width"); }')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.removeProperty("height")')

        handle = promise.wait
        expect(handle).to be_truthy
        handle.dispose if handle
        element.dispose
      end
    end
  end

  it 'should wait for element to be visible recursively' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div#inner', visible: true).tap { promise_resolved = true }
        end

        page.set_content('<div style="display: none; visibility: hidden;"><div id="inner">hi</div></div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.removeProperty("display")')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.removeProperty("visibility")')

        handle = promise.wait
        expect(handle).to be_truthy
        handle.dispose if handle
        element.dispose
      end
    end
  end

  it 'should wait for element to be hidden (visibility)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', hidden: true).tap { promise_resolved = true }
        end

        page.set_content('<div style="display: block;">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.setProperty("visibility", "hidden")')

        result = promise.wait
        expect(result).to be_truthy
        result.dispose if result.respond_to?(:dispose)
        element.dispose
      end
    end
  end

  it 'should wait for element to be hidden (display)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', hidden: true).tap { promise_resolved = true }
        end

        page.set_content('<div style="display: block;">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.setProperty("display", "none")')

        result = promise.wait
        expect(result).to be_truthy
        result.dispose if result.respond_to?(:dispose)
        element.dispose
      end
    end
  end

  it 'should wait for element to be hidden (bounding box)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', hidden: true).tap { promise_resolved = true }
        end

        page.set_content('<div>text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.style.setProperty("height", "0")')

        result = promise.wait
        expect(result).to be_truthy
        result.dispose if result.respond_to?(:dispose)
        element.dispose
      end
    end
  end

  it 'should wait for element to be hidden (removal)' do
    with_test_state do |page:, **|
      promise_resolved = false

      Sync do
        promise = Async do
          page.wait_for_selector('div', hidden: true).tap { promise_resolved = true }
        end

        page.set_content('<div>text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

        Async do |task|
          task.sleep(0.04)
          expect(promise_resolved).to be false
        end.wait

        element.evaluate('element => element.remove()')

        result = promise.wait
        expect(result).to be_falsey
        result.dispose if result.respond_to?(:dispose)
        element.dispose
      end
    end
  end

  it 'should return nil if waiting to hide non-existing element' do
    with_test_state do |page:, **|
      handle = page.wait_for_selector('non-existing', hidden: true)
      expect(handle).to be_nil
    end
  end

  it 'should respect timeout' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      expect {
        page.wait_for_selector('div', timeout: 10)
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /Waiting for selector `div` failed/)
    end
  end

  it 'should have an error message specifically for awaiting hidden element' do
    with_test_state do |page:, **|
      page.set_content('<div>text</div>')

      expect {
        page.wait_for_selector('div', hidden: true, timeout: 10)
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /Waiting for selector `div` failed/)
    end
  end

  it 'should respond to node attribute mutation' do
    with_test_state do |page:, **|
      div_found = false

      Sync do
        watcher = Async do
          handle = page.wait_for_selector('.zombo')
          begin
            div_found = true
            true
          ensure
            handle&.dispose
          end
        end

        page.set_content('<div class="notZombo"></div>')
        expect(div_found).to be false

        page.evaluate('() => { document.querySelector("div").className = "zombo"; }')

        expect(watcher.wait).to be true
      end
    end
  end

  it 'should return the element handle' do
    with_test_state do |page:, **|
      Sync do
        watcher = Async do
          page.wait_for_selector('.zombo')
        end

        page.set_content('<div class="zombo">anything</div>')

        handle = watcher.wait
        text = page.evaluate('(element) => element ? element.textContent : null', handle)
        expect(text).to eq('anything')
        handle.dispose
      end
    end
  end

  it 'should have correct stack trace for timeout' do
    with_test_state do |page:, **|
      error = nil

      begin
        page.wait_for_selector('.zombo', timeout: 10)
      rescue => e
        error = e
      end

      expect(error).not_to be_nil
      stack = Array(error.backtrace).join("\n")
      expect(stack).to include('Waiting for selector `.zombo` failed')
    end
  end

  describe 'xpath' do
    let(:xpath_add_element) do
      <<~JAVASCRIPT
        (tag) => {
          return document.body.appendChild(document.createElement(tag));
        }
      JAVASCRIPT
    end

    it 'should support some fancy xpath' do
      with_test_state do |page:, **|
        page.set_content('<p>red herring</p><p>hello  world  </p>')

        handle = page.wait_for_selector('xpath/.//p[normalize-space(.)="hello world"]')
        text = page.evaluate('(element) => element ? element.textContent : null', handle)
        expect(text).to eq('hello  world  ')
        handle.dispose
      end
    end

    it 'should respect timeout' do
      with_test_state do |page:, **|
        expect {
          page.wait_for_selector('xpath/.//div', timeout: 10)
        }.to raise_error(Puppeteer::Bidi::TimeoutError, /Waiting for selector `\.\/\/div` failed/)
      end
    end

    it 'should run in specified frame' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        attach_frame(page, 'frame1', server.empty_page)
        frame2 = attach_frame(page, 'frame2', server.empty_page)
        frame1 = page.frames[1]

        resolved_frame = nil

        Sync do
          watcher = Async do
            frame2.wait_for_selector('xpath/.//div').tap { |element| resolved_frame = element&.frame }
          end

          frame1.evaluate(xpath_add_element, 'div')
          frame2.evaluate(xpath_add_element, 'div')

          element = watcher.wait
          expect(resolved_frame).to eq(frame2)
          element.dispose
        end
      end
    end

    it 'should throw when frame is detached' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        frame = attach_frame(page, 'frame1', server.empty_page)
        wait_error = nil

        Sync do
          watcher = Async do
            frame.wait_for_selector('xpath/.//*[@class="box"]')
          rescue => error
            wait_error = error
            nil
          end

          detach_frame(page, 'frame1')
          watcher.wait
        end

        expect(wait_error).not_to be_nil
        message = wait_error.message
        expect(message.include?('Waiting for selector `.//*[@class="box"]` failed') || message.include?('Frame detached')).to be true
      end
    end

    it 'hidden should wait for display: none' do
      with_test_state do |page:, **|
        div_hidden = false

        page.set_content('<div style="display: block;">text</div>')

        Sync do
          watcher = Async do
            handle = page.wait_for_selector('xpath/.//div', hidden: true)
            begin
              div_hidden = true
              true
            ensure
              handle&.dispose
            end
          end

          page.wait_for_selector('xpath/.//div')
          expect(div_hidden).to be false

          page.evaluate('() => { document.querySelector("div").style.setProperty("display", "none"); }')

          expect(watcher.wait).to be true
          expect(div_hidden).to be true
        end
      end
    end

    it 'hidden should return nil if the element is not found' do
      with_test_state do |page:, **|
        handle = page.wait_for_selector('xpath/.//div', hidden: true)
        expect(handle).to be_nil
      end
    end

    it 'hidden should return an empty element handle if the element is found' do
      with_test_state do |page:, **|
        page.set_content('<div style="display: none;">text</div>')

        handle = page.wait_for_selector('xpath/.//div', hidden: true)
        expect(handle).to be_a(Puppeteer::Bidi::ElementHandle)
        handle.dispose
      end
    end

    it 'should return the element handle' do
      with_test_state do |page:, **|
        Sync do
          watcher = Async do
            page.wait_for_selector('xpath/.//*[@class="zombo"]')
          end

          page.set_content('<div class="zombo">anything</div>')

          handle = watcher.wait
          text = page.evaluate('(element) => element ? element.textContent : null', handle)
          expect(text).to eq('anything')
          handle.dispose
        end
      end
    end

    it 'should allow you to select a text node' do
      with_test_state do |page:, **|
        page.set_content('<div>some text</div>')

        text_handle = page.wait_for_selector('xpath/.//div/text()')
        node_type_handle = text_handle.get_property('nodeType')
        expect(node_type_handle.json_value).to eq(3)
        node_type_handle.dispose
        text_handle.dispose
      end
    end

    it 'should allow you to select an element with single slash' do
      with_test_state do |page:, **|
        page.set_content('<div>some text</div>')

        handle = page.wait_for_selector('xpath/html/body/div')
        text = page.evaluate('(element) => element ? element.textContent : null', handle)
        expect(text).to eq('some text')
        handle.dispose
      end
    end
  end
end

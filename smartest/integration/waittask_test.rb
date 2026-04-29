# frozen_string_literal: true

require "test_helper"

  test(['Frame.waitForFunction', 'should accept a string'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    watchdog = Async do
      page.wait_for_function("() => window.__FOO === 1")
    end
    page.evaluate("() => window.__FOO = 1")
    watchdog.wait
  end

  test(['Frame.waitForFunction', 'should accept a string with block'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    page.wait_for_function("() => window.__FOO === 1") do
      page.evaluate("() => window.__FOO = 1")
    end
  end

  test(['Frame.waitForFunction', 'should work when resolved right before execution context disposal'].join(" ")) do |page:, server:|
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

  test(['Frame.waitForFunction', 'should poll on interval'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)
    page.evaluate("() => { delete window.__FOO }")

    start_time = Time.now

    watchdog = Async do
      page.wait_for_function("() => window.__FOO === 'hit'", polling: 500)
    end
    Async do
      page.evaluate("() => setTimeout(() => { window.__FOO = 'hit' }, 50)")
    end

    watchdog.wait
    elapsed = ((Time.now - start_time) * 1000).to_i

    expect(elapsed).to be >= 250
  end

  test(['Frame.waitForFunction', 'should poll on interval with block'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)
    page.evaluate("() => { delete window.__FOO }")

    start_time = Time.now

    page.wait_for_function("() => window.__FOO === 'hit'", polling: 500) do
      page.evaluate("() => setTimeout(() => { window.__FOO = 'hit' }, 50)")
    end

    elapsed = ((Time.now - start_time) * 1000).to_i

    expect(elapsed).to be >= 250
  end

  test(['Frame.waitForFunction', 'should poll on mutation'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

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

  test(['Frame.waitForFunction', 'should poll on mutation async'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

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

  test(['Frame.waitForFunction', 'should poll on raf'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    watchdog = Async do
      page.wait_for_function("async () => window.__FOO === 'hit'", polling: 'raf')
    end
    page.evaluate("async () => window.__FOO = 'hit'")

    watchdog.wait
  end

  test(['Frame.waitForFunction', 'should poll on raf async'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    watchdog = Async do
      page.wait_for_function("async () => window.__FOO === 'hit'", polling: 'raf')
    end

    page.evaluate("() => window.__FOO = 'hit'")

    handle = watchdog.wait
    expect(handle).not_to be_nil
    handle.dispose
  end

  test(['Frame.waitForFunction', 'should work with strict CSP policy'].join(" ")) do |page:, server:|
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

  test(['Frame.waitForFunction', 'should throw on negative polling interval'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    expect {
      page.wait_for_function("() => true", polling: -10)
    }.to raise_error(/Cannot poll with non-positive interval/)
  end

  test(['Frame.waitForFunction', 'should return the success value as a JSHandle'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    result = page.wait_for_function("() => 5")
    expect(result.json_value).to eq(5)
    result.dispose
  end

  test(['Frame.waitForFunction', 'should return the window as a success value'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    result = page.wait_for_function("() => window")
    expect(result).not_to be_nil
    result.dispose
  end

  test(['Frame.waitForFunction', 'should accept ElementHandle arguments'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)
    page.set_content('<div></div>')

    div = page.query_selector('div')

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

    div.dispose
  end

  test(['Frame.waitForFunction', 'should respect timeout'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    expect {
      page.wait_for_function("() => false", timeout: 10)
    }.to raise_error(Puppeteer::Bidi::TimeoutError, /10ms exceeded/)
  end

  test(['Frame.waitForFunction', 'should respect default timeout'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    page.set_default_timeout(10)

    expect {
      page.wait_for_function("() => false")
    }.to raise_error(Puppeteer::Bidi::TimeoutError, /10ms exceeded/)
  end

  test(['Frame.waitForFunction', 'should disable timeout when set to 0'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

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

  test(['Frame.waitForFunction', 'should survive cross-process navigation'].join(" ")) do |page:, server:|
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

  test(['Frame.waitForFunction', 'should survive navigations'].join(" ")) do |page:, server:|
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

  test(['Frame.waitForFunction', 'should be cancellable with an abort signal'].join(" ")) do
    skip 'Requires JS-specific AbortController/signal support.'
  end

  test(['Frame.waitForFunction', 'should not cause an unhandled error when aborted'].join(" ")) do
    skip 'Requires JS-specific AbortController/signal support.'
  end

  test(['Frame.waitForFunction', 'can start multiple tasks without warnings when aborted'].join(" ")) do
    skip 'Requires JS-specific AbortController/signal support.'
  end

  def add_element
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

  test(['Frame.waitForSelector', 'should immediately resolve promise if node exists'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    frame = page.main_frame

    element = frame.wait_for_selector('*') do
      page.evaluate(add_element, 'div')
    end

    expect(element).to be_a(Puppeteer::Bidi::ElementHandle)

    element = page.wait_for_selector('div')
    expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
  end

  test(['Frame.waitForSelector', 'should be cancellable'].join(" ")) do
    skip 'AbortController/signal support needed for cancellation, which is JS-specific.'
  end

  test(['Frame.waitForSelector', 'should work with removed MutationObserver'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    page.evaluate('() => { delete window.MutationObserver; }')

    handle = page.wait_for_selector('.zombo') do
      page.set_content('<div class="zombo">anything</div>')
    end

    text = page.evaluate('(element) => element.textContent', handle)

    expect(text).to eq('anything')
    handle.dispose
  end

  test(['Frame.waitForSelector', 'should resolve promise when node is added'].join(" ")) do |page:, server:|
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

  test(['Frame.waitForSelector', 'should work when node is added through innerHTML'].join(" ")) do |page:, server:|
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

  test(['Frame.waitForSelector', 'should work when node is added in a shadow root'].join(" ")) do |page:, server:|
    pending if true
    page.goto(server.empty_page)

    handle = page.wait_for_selector('div >>> h1') do
      page.evaluate(add_element, 'div')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(page.evaluate('() => !!document.querySelector("div >>> h1")')).to be false

      page.evaluate(<<~JS)
        () => {
          const host = document.querySelector('div');
          const shadow = host.attachShadow({ mode: 'open' });
          const h1 = document.createElement('h1');
          h1.textContent = 'inside';
          shadow.appendChild(h1);
        }
      JS
    end

    text = handle.evaluate('(element) => element.textContent')
    expect(text).to eq('inside')
    handle.dispose
  end

  test(['Frame.waitForSelector', 'should work for selector with a pseudo class'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    handle = page.wait_for_selector('input:focus') do
      page.set_content('<input></input>')
      page.click('input')
    end

    expect(handle).to be_a(Puppeteer::Bidi::ElementHandle)
    handle.dispose
  end

  test(['Frame.waitForSelector', 'Page.waitForSelector is shortcut for main frame'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    other_frame = attach_frame(page, 'frame1', server.empty_page)
    element_handle = page.wait_for_selector('div') do
      other_frame.evaluate(add_element, 'div')
      page.evaluate(add_element, 'div')
    end

    expect(element_handle.frame.browsing_context.id).to eq(page.main_frame.browsing_context.id)
  end

  test(['Frame.waitForSelector', 'should run in specified frame'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    frame1 = attach_frame(page, 'frame1', server.empty_page)
    frame2 = attach_frame(page, 'frame2', server.empty_page)

    element = frame2.wait_for_selector('div') do
      frame1.evaluate(add_element, 'div')
      frame2.evaluate(add_element, 'div')
    end

    expect(element.frame.browsing_context.id).to eq(frame2.browsing_context.id)
    element.dispose
  end

  test(['Frame.waitForSelector', 'should throw when frame is detached'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    frame = attach_frame(page, 'frame1', server.empty_page)

    wait_error = nil

    begin
      frame.wait_for_selector('.box') do
        detach_frame(page, 'frame1')
      end
    rescue => error
      wait_error = error
    end

    expect(wait_error).not_to be_nil
    message = wait_error.message
    expect(
      message.include?('Waiting for selector `.box` failed') ||
      message.include?('Frame detached') ||
      message.include?('Browsing context already disposed')
    ).to be true
  end

  test(['Frame.waitForSelector', 'should survive cross-process navigation'].join(" ")) do |page:, server:|
    navigation_task = nil

    handle = page.wait_for_selector('.box') do
      navigation_task = Async do
        page.goto(server.empty_page)
        page.goto(server.empty_page)
        page.goto("#{server.cross_process_prefix}/grid.html")
      end
    end

    navigation_task&.wait
    expect(handle).to be_a(Puppeteer::Bidi::ElementHandle)
    handle.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be visible (display)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    handle = page.wait_for_selector('div', visible: true) do
      page.set_content('<div style="display: none">text</div>')

      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.removeProperty("display")')
    end

    promise_resolved = true
    expect(handle).to be_truthy
    handle.dispose if handle
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be visible without DOM mutations'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    handle = page.wait_for_selector('div', visible: true) do
      page.set_content(<<~HTML)
        <style>
          div { display: none; }
        </style>
        <div>text</div>
      HTML

      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')
      expect(element_handle).not_to be_nil

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      page.evaluate(<<~JS)
        () => {
          const sheet = new CSSStyleSheet();
          sheet.replaceSync('div { display: block; }');
          document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
        }
      JS
    end

    promise_resolved = true
    expect(handle).to be_truthy
    handle.dispose if handle
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be visible (visibility)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    handle = page.wait_for_selector('div', visible: true) do
      page.set_content('<div style="visibility: hidden">text</div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.setProperty("visibility", "collapse")')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.removeProperty("visibility")')
    end

    promise_resolved = true
    expect(handle).to be_truthy
    handle.dispose if handle
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be visible (bounding box)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    handle = page.wait_for_selector('div', visible: true) do
      page.set_content('<div style="width: 0">text</div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => { element.style.setProperty("height", "0"); element.style.removeProperty("width"); }')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.removeProperty("height")')
    end

    promise_resolved = true
    expect(handle).to be_truthy
    handle.dispose if handle
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be visible recursively'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    handle = page.wait_for_selector('div#inner', visible: true) do
      page.set_content('<div style="display: none; visibility: hidden;"><div id="inner">hi</div></div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.removeProperty("display")')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.removeProperty("visibility")')
    end

    promise_resolved = true
    expect(handle).to be_truthy
    handle.dispose if handle
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be hidden (visibility)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    result = page.wait_for_selector('div', hidden: true) do
      page.set_content('<div style="display: block;">text</div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.setProperty("visibility", "hidden")')
    end

    promise_resolved = true
    expect(result).to be_truthy
    result.dispose if result.respond_to?(:dispose)
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be hidden (display)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    result = page.wait_for_selector('div', hidden: true) do
      page.set_content('<div style="display: block;">text</div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.setProperty("display", "none")')
    end

    promise_resolved = true
    expect(result).to be_truthy
    result.dispose if result.respond_to?(:dispose)
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be hidden (bounding box)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    result = page.wait_for_selector('div', hidden: true) do
      page.set_content('<div>text</div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.style.setProperty("height", "0")')
    end

    promise_resolved = true
    expect(result).to be_truthy
    result.dispose if result.respond_to?(:dispose)
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should wait for element to be hidden (removal)'].join(" ")) do |page:|
    promise_resolved = false

    element_handle = nil
    result = page.wait_for_selector('div', hidden: true) do
      page.set_content('<div>text</div>')
      element_handle = page.evaluate_handle('() => document.getElementsByTagName("div")[0]')

      page.evaluate('() => new Promise(resolve => setTimeout(resolve, 40))')
      expect(promise_resolved).to be false

      element_handle.evaluate('element => element.remove()')
    end

    promise_resolved = true
    expect(result).to be_falsey
    result.dispose if result.respond_to?(:dispose)
    element_handle&.dispose
  end

  test(['Frame.waitForSelector', 'should return nil if waiting to hide non-existing element'].join(" ")) do |page:|
    handle = page.wait_for_selector('non-existing', hidden: true)
    expect(handle).to be_nil
  end

  test(['Frame.waitForSelector', 'should respect timeout'].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    expect {
      page.wait_for_selector('div', timeout: 10)
    }.to raise_error(Puppeteer::Bidi::TimeoutError, /Waiting for selector `div` failed/)
  end

  test(['Frame.waitForSelector', 'should have an error message specifically for awaiting hidden element'].join(" ")) do |page:|
    page.set_content('<div>text</div>')

    expect {
      page.wait_for_selector('div', hidden: true, timeout: 10)
    }.to raise_error(Puppeteer::Bidi::TimeoutError, /Waiting for selector `div` failed/)
  end

  test(['Frame.waitForSelector', 'should respond to node attribute mutation'].join(" ")) do |page:|
    handle = page.wait_for_selector('.zombo') do
      page.set_content('<div class="notZombo"></div>')
      expect(page.evaluate('() => document.querySelector(".zombo")')).to be_nil

      page.evaluate('() => { document.querySelector("div").className = "zombo"; }')
    end

    expect(handle).not_to be_nil
    handle.dispose
  end

  test(['Frame.waitForSelector', 'should return the element handle'].join(" ")) do |page:|
    handle = page.wait_for_selector('.zombo') do
      page.set_content('<div class="zombo">anything</div>')
    end

    text = page.evaluate('(element) => element ? element.textContent : null', handle)
    expect(text).to eq('anything')
    handle.dispose
  end

  test(['Frame.waitForSelector', 'should have correct stack trace for timeout'].join(" ")) do |page:|
    expect {
      page.wait_for_selector('.zombo', timeout: 10)
    }.to raise_error(/Waiting for selector `.zombo` faile/) do |err|
        expect(err.backtrace.join("\n")).to include('waittask_test.rb')
    end
  end

    def xpath_add_element
      <<~JAVASCRIPT
        (tag) => {
          return document.body.appendChild(document.createElement(tag));
        }
      JAVASCRIPT
    end

    test(['Frame.waitForSelector', 'xpath', 'should support some fancy xpath'].join(" ")) do |page:|
      page.set_content('<p>red herring</p><p>hello  world  </p>')

      handle = page.wait_for_selector('xpath/.//p[normalize-space(.)="hello world"]')
      text = page.evaluate('(element) => element ? element.textContent : null', handle)
      expect(text).to eq('hello  world  ')
      handle.dispose
    end

    test(['Frame.waitForSelector', 'xpath', 'should respect timeout'].join(" ")) do |page:|
      expect {
        page.wait_for_selector('xpath/.//div', timeout: 10)
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /Waiting for selector `\.\/\/div` failed/)
    end

    test(['Frame.waitForSelector', 'xpath', 'should run in specified frame'].join(" ")) do |page:, server:|
      page.goto(server.empty_page)

      attach_frame(page, 'frame1', server.empty_page)
      frame2 = attach_frame(page, 'frame2', server.empty_page)
      frame1 = page.frames[1]

      element = frame2.wait_for_selector('xpath/.//div') do
        frame1.evaluate(xpath_add_element, 'div')
        frame2.evaluate(xpath_add_element, 'div')
      end

      expect(element&.frame&.browsing_context&.id).to eq(frame2.browsing_context.id)
      element.dispose
    end

    test(['Frame.waitForSelector', 'xpath', 'should throw when frame is detached'].join(" ")) do |page:, server:|
      page.goto(server.empty_page)

      frame = attach_frame(page, 'frame1', server.empty_page)
      wait_error = nil

      begin
        frame.wait_for_selector('xpath/.//*[@class="box"]') do
          detach_frame(page, 'frame1')
        end
      rescue => error
        wait_error = error
      end

      expect(wait_error).not_to be_nil
      message = wait_error.message
      expect(
        message.include?('Waiting for selector `.//*[@class="box"]` failed') ||
        message.include?('Frame detached') ||
        message.include?('Browsing context already disposed')
      ).to be true
    end

    test(['Frame.waitForSelector', 'xpath', 'hidden should wait for display: none'].join(" ")) do |page:|
      page.set_content('<div style="display: block;">text</div>')

      handle = page.wait_for_selector('xpath/.//div', hidden: true) do
        expect(page.evaluate('() => getComputedStyle(document.querySelector("div")).display')).to eq('block')
        page.evaluate('() => { document.querySelector("div").style.setProperty("display", "none"); }')
      end

      expect(handle).to be_truthy
      handle.dispose if handle.respond_to?(:dispose)
    end

    test(['Frame.waitForSelector', 'xpath', 'hidden should return nil if the element is not found'].join(" ")) do |page:|
      handle = page.wait_for_selector('xpath/.//div', hidden: true)
      expect(handle).to be_nil
    end

    test(['Frame.waitForSelector', 'xpath', 'hidden should return an empty element handle if the element is found'].join(" ")) do |page:|
      page.set_content('<div style="display: none;">text</div>')

      handle = page.wait_for_selector('xpath/.//div', hidden: true)
      expect(handle).to be_a(Puppeteer::Bidi::ElementHandle)
      handle.dispose
    end

    test(['Frame.waitForSelector', 'xpath', 'should return the element handle'].join(" ")) do |page:|
      handle = page.wait_for_selector('xpath/.//*[@class="zombo"]') do
        page.set_content('<div class="zombo">anything</div>')
      end

      text = page.evaluate('(element) => element ? element.textContent : null', handle)
      expect(text).to eq('anything')
      handle.dispose
    end

    test(['Frame.waitForSelector', 'xpath', 'should allow you to select a text node'].join(" ")) do |page:|
      page.set_content('<div>some text</div>')

      text_handle = page.wait_for_selector('xpath/.//div/text()')
      node_type_handle = text_handle.get_property('nodeType')
      expect(node_type_handle.json_value).to eq(3)
      node_type_handle.dispose
      text_handle.dispose
    end

    test(['Frame.waitForSelector', 'xpath', 'should allow you to select an element with single slash'].join(" ")) do |page:|
      page.set_content('<div>some text</div>')

      handle = page.wait_for_selector('xpath/html/body/div')
      text = page.evaluate('(element) => element ? element.textContent : null', handle)
      expect(text).to eq('some text')
      handle.dispose
    end

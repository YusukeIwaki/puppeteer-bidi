# frozen_string_literal: true

require "test_helper"

  test(['Page.click', 'should click the button'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    page.click('button')
    expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should click svg'].join(" ")) do |page:|
    page.set_content(<<~HTML)
      <svg height="100" width="100">
        <circle onclick="javascript:window.__CLICKED=42"
                cx="50" cy="50" r="40"
                stroke="black" stroke-width="3" fill="red" />
      </svg>
    HTML
    page.click('circle')
    expect(page.evaluate('() => globalThis.__CLICKED')).to eq(42)
  end

  test(['Page.click', 'should click the button if window.Node is removed'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    page.evaluate('() => delete window.Node')
    page.click('button')
    expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should click on a span with an inline element inside'].join(" ")) do |page:|
    page.set_content(<<~HTML)
      <style>
        span::before {
          content: 'q';
        }
      </style>
      <span onclick="javascript:window.CLICKED=42"></span>
    HTML
    page.click('span')
    expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
  end

  test(['Page.click', 'should not throw UnhandledPromiseRejection when page closes'].join(" ")) do |page:|
    skip 'Browser.new_page not yet implemented'

    new_page = page.browser.new_page
    # This should not throw
    begin
      new_page.close
      new_page.mouse.click(1, 2)
    rescue StandardError
      # Expected to fail, but should not throw UnhandledPromiseRejection
    end
  end

  test(['Page.click', 'should click the button after navigation'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    page.click('button')
    page.goto("#{server.prefix}/input/button.html")
    page.click('button')
    expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should click with disabled javascript'].join(" ")) do |page:, server:|
    # Firefox does not yet support browsingContext.setScriptingEnabled BiDi command
    pending 'browsingContext.setScriptingEnabled not supported by Firefox yet'

    page.set_javascript_enabled(false)
    page.goto("#{server.prefix}/wrappedlink.html")
    page.click('a')
    # wait_for_navigation is called implicitly
    expect(page.url).to eq("#{server.prefix}/wrappedlink.html#clicked")
  end

  test(['Page.click', 'should scroll and click with disabled javascript'].join(" ")) do |page:, server:|
    # Firefox does not yet support browsingContext.setScriptingEnabled BiDi command
    pending 'browsingContext.setScriptingEnabled not supported by Firefox yet'

    page.set_javascript_enabled(false)
    page.goto("#{server.prefix}/wrappedlink.html")
    body = page.wait_for_selector('body')
    body.evaluate("el => { el.style.paddingTop = '3000px'; }")
    page.click('a')
    # wait_for_navigation is called implicitly
    expect(page.url).to eq("#{server.prefix}/wrappedlink.html#clicked")
  end

  test(['Page.click', 'should click when one of inline box children is outside of viewport'].join(" ")) do |page:|
    page.set_content(<<~HTML)
      <style>
        i {
          position: absolute;
          top: -1000px;
        }
      </style>
      <span onclick="javascript:window.CLICKED = 42;"><i>woof</i><b>doggo</b></span>
    HTML
    page.click('span')
    expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
  end

  test(['Page.click', 'should select the text by triple clicking'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/textarea.html")
    page.focus('textarea')
    text = "This is the text that we are going to try to select. Let's see how it goes."
    page.keyboard.type(text)

    page.evaluate(<<~JS)
      () => {
        window.clicks = [];
        window.addEventListener('click', event => window.clicks.push(event.detail));
      }
    JS

    page.click('textarea', count: 3)

    # Verify click details (1, 2, 3 for single, double, triple click)
    clicks = page.evaluate('() => window.clicks')
    expect(clicks).to eq([1, 2, 3])

    # Verify text selection
    result = page.evaluate(<<~JS)
      () => {
        const textarea = document.querySelector('textarea');
        return textarea.value.substring(
          textarea.selectionStart,
          textarea.selectionEnd
        );
      }
    JS
    expect(result).to eq(text)
  end

  test(['Page.click', 'should click offscreen buttons'].join(" ")) do |page:, server:|
    skip 'page.on("console") not yet implemented'

    page.goto("#{server.prefix}/offscreenbuttons.html")
    messages = []
    page.on('console') do |msg|
      messages << msg.text if msg.type == 'log'
    end

    11.times do |i|
      page.evaluate('() => window.scrollTo(0, 0)')
      page.click("#btn#{i}")
    end

    expect(messages).to eq([
      'button #0 clicked',
      'button #1 clicked',
      'button #2 clicked',
      'button #3 clicked',
      'button #4 clicked',
      'button #5 clicked',
      'button #6 clicked',
      'button #7 clicked',
      'button #8 clicked',
      'button #9 clicked',
      'button #10 clicked'
    ])
  end

  test(['Page.click', 'should click half-offscreen elements'].join(" ")) do |page:|
    page.set_content(<<~HTML)
      <!DOCTYPE html>
      <style>
        body { overflow: hidden; }
        #target {
          width: 200px;
          height: 200px;
          background: red;
          position: fixed;
          left: -150px;
          top: -150px;
        }
      </style>
      <div id="target" onclick="window.CLICKED=true;"></div>
    HTML

    page.click('#target')
    expect(page.evaluate('() => globalThis.CLICKED')).to be true

    element = page.query_selector('#target')
    bounding_box = element.bounding_box
    expect(bounding_box.width).to eq(200)
    expect(bounding_box.height).to eq(200)
    expect(bounding_box.x).to eq(-150)
    expect(bounding_box.y).to eq(-150)

    clickable_point = element.clickable_point
    expect(clickable_point.x).to eq(25)
    expect(clickable_point.y).to eq(25)
  end

  test(['Page.click', 'should click wrapped links'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/wrappedlink.html")
    page.click('a')
    expect(page.evaluate('() => globalThis.__clicked')).to be true
  end

  test(['Page.click', 'should click on checkbox input and toggle'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/checkbox.html")
    expect(page.evaluate('() => globalThis.result.check')).to be_nil
    page.click('input#agree')
    expect(page.evaluate('() => globalThis.result.check')).to be true
    expect(page.evaluate('() => globalThis.result.events')).to eq(
      %w[mouseover mouseenter mousemove mousedown mouseup click input change]
    )
    page.click('input#agree')
    expect(page.evaluate('() => globalThis.result.check')).to be false
  end

  test(['Page.click', 'should click on checkbox label and toggle'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/checkbox.html")
    expect(page.evaluate('() => globalThis.result.check')).to be_nil
    page.click('label[for="agree"]')
    expect(page.evaluate('() => globalThis.result.check')).to be true
    expect(page.evaluate('() => globalThis.result.events')).to eq(%w[click input change])
    page.click('label[for="agree"]')
    expect(page.evaluate('() => globalThis.result.check')).to be false
  end

  test(['Page.click', 'should fail to click a missing button'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    expect {
      page.click('button.does-not-exist')
    }.to raise_error(Puppeteer::Bidi::SelectorNotFoundError, /button\.does-not-exist/)
  end

  test(['Page.click', 'should not hang with touch-enabled viewports'].join(" ")) do |page:|
    # @see https://github.com/puppeteer/puppeteer/issues/161
    # Equivalent to KnownDevices['iPhone 6'].viewport in upstream spec.
    page.set_viewport(
      width: 375,
      height: 667,
      device_scale_factor: 2,
      is_mobile: true,
      has_touch: true,
      is_landscape: false
    )
    page.mouse.down
    page.mouse.move(100, 10)
    page.mouse.up
  end

  test(['Page.click', 'should scroll and click the button'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/scrollable.html")
    page.click('#button-5')
    expect(page.evaluate("() => document.querySelector('#button-5').textContent")).to eq('clicked')
    page.click('#button-80')
    expect(page.evaluate("() => document.querySelector('#button-80').textContent")).to eq('clicked')
  end

  test(['Page.click', 'should double click the button'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    page.evaluate(<<~JS)
      () => {
        globalThis.double = false;
        const button = document.querySelector('button');
        button.addEventListener('dblclick', () => {
          globalThis.double = true;
        });
      }
    JS

    button = page.query_selector('button')
    button.click(count: 2)
    expect(page.evaluate('double')).to be true
    expect(page.evaluate('result')).to eq('Clicked')
  end

  test(['Page.click', 'should double click multiple times'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    page.evaluate(<<~JS)
      () => {
        globalThis.count = 0;
        const button = document.querySelector('button');
        button.addEventListener('dblclick', () => {
          globalThis.count++;
        });
      }
    JS

    button = page.query_selector('button')
    button.click(count: 2)
    button.click(count: 2)
    expect(page.evaluate('count')).to eq(2)
  end

  test(['Page.click', 'should click a partially obscured button'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/button.html")
    page.evaluate(<<~JS)
      () => {
        const button = document.querySelector('button');
        button.textContent = 'Some really long text that will go offscreen';
        button.style.position = 'absolute';
        button.style.left = '368px';
      }
    JS

    page.click('button')
    expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should click a rotated button'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/rotatedButton.html")
    page.click('button')
    expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should fire contextmenu event on right click'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/scrollable.html")
    page.click('#button-8', button: 'right')
    expect(page.evaluate("() => document.querySelector('#button-8').textContent")).to eq('context menu')
  end

  test(['Page.click', 'should fire aux event on middle click'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/scrollable.html")
    page.click('#button-8', button: 'middle')
    expect(page.evaluate("() => document.querySelector('#button-8').textContent")).to eq('aux click')
  end

  test(['Page.click', 'should fire back click'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/scrollable.html")
    page.click('#button-8', button: 'back')
    expect(page.evaluate("() => document.querySelector('#button-8').textContent")).to eq('back click')
  end

  test(['Page.click', 'should fire forward click'].join(" ")) do |page:, server:|
    page.goto("#{server.prefix}/input/scrollable.html")
    page.click('#button-8', button: 'forward')
    expect(page.evaluate("() => document.querySelector('#button-8').textContent")).to eq('forward click')
  end

  test(['Page.click', 'should click links which cause navigation'].join(" ")) do |page:, server:|
    page.set_content("<a href=\"#{server.empty_page}\">empty.html</a>")
    # This should not hang
    page.click('a')
  end

  test(['Page.click', 'should click the button inside an iframe'].join(" ")) do |page:, server:|
    skip 'Frame support not yet implemented'

    page.goto(server.empty_page)
    page.set_content('<div style="width:100px;height:100px">spacer</div>')
    # attach_frame helper would be needed
    page.evaluate(<<~JS, server.prefix)
      (prefix) => {
        const frame = document.createElement('iframe');
        frame.id = 'button-test';
        frame.src = prefix + '/input/button.html';
        document.body.appendChild(frame);
        return new Promise(resolve => frame.onload = resolve);
      }
    JS

    frame = page.frames[1]
    button = frame.query_selector('button')
    button.click
    expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should click the button with fixed position inside an iframe'].join(" ")) do |page:, server:|
    skip 'Frame support not yet implemented'

    page.goto(server.empty_page)
    page.set_viewport(width: 500, height: 500)
    page.set_content('<div style="width:100px;height:2000px">spacer</div>')
    page.evaluate(<<~JS, server.cross_process_prefix)
      (prefix) => {
        const frame = document.createElement('iframe');
        frame.id = 'button-test';
        frame.src = prefix + '/input/button.html';
        document.body.appendChild(frame);
        return new Promise(resolve => frame.onload = resolve);
      }
    JS

    frame = page.frames[1]
    frame.eval_on_selector('button', "button => button.style.setProperty('position', 'fixed')")
    frame.click('button')
    expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
  end

  test(['Page.click', 'should click the button with deviceScaleFactor set'].join(" ")) do |page:, server:|
    skip 'Frame support not yet implemented'

    page.set_viewport(width: 400, height: 400, device_scale_factor: 5)
    expect(page.evaluate('() => window.devicePixelRatio')).to eq(5)
    page.set_content('<div style="width:100px;height:100px">spacer</div>')
    page.evaluate(<<~JS, server.prefix)
      (prefix) => {
        const frame = document.createElement('iframe');
        frame.id = 'button-test';
        frame.src = prefix + '/input/button.html';
        document.body.appendChild(frame);
        return new Promise(resolve => frame.onload = resolve);
      }
    JS

    frame = page.frames[1]
    button = frame.query_selector('button')
    button.click
    expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
  end

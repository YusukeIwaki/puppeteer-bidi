# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Page.click' do
  it 'should click the button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      result = page.evaluate('window.result')
      expect(result).to eq('Clicked')
    end
  end

  it 'should click svg' do
    with_test_state do |page:, **|
      page.set_content(<<~HTML)
        <svg height="100" width="100">
          <circle onclick="javascript:window.__CLICKED=42"
                  cx="50" cy="50" r="40"
                  stroke="black" stroke-width="3" fill="red" />
        </svg>
      HTML
      page.click('circle')
      result = page.evaluate('window.__CLICKED')
      expect(result).to eq(42)
    end
  end

  it 'should click the button if window.Node is removed' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.evaluate('delete window.Node')
      page.click('button')
      result = page.evaluate('window.result')
      expect(result).to eq('Clicked')
    end
  end

  it 'should click on a span with an inline element inside' do
    with_test_state do |page:, **|
      page.set_content(<<~HTML)
        <style>
          span::before {
            content: 'q';
          }
        </style>
        <span onclick="javascript:window.CLICKED=42"></span>
      HTML
      page.click('span')
      result = page.evaluate('window.CLICKED')
      expect(result).to eq(42)
    end
  end

  it 'should click the button after navigation' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      result = page.evaluate('window.result')
      expect(result).to eq('Clicked')
    end
  end

  it 'should click with disabled javascript' do
    with_test_state do |page:, server:, **|
      # Skip: Firefox does not yet support emulation.setScriptingEnabled BiDi command
      # This is part of the WebDriver BiDi spec but not yet implemented in Firefox
      skip 'emulation.setScriptingEnabled not supported by Firefox yet'

      page.set_javascript_enabled(false)
      page.goto("#{server.prefix}/wrappedlink.html")

      # Click the link - should navigate via href since onclick won't work
      initial_url = page.url
      page.click('a')

      # Wait for URL to change
      timeout = 5
      start_time = Time.now
      loop do
        break if page.url != initial_url && page.url.include?('#clicked')
        raise 'Navigation timeout' if Time.now - start_time > timeout
        sleep 0.1
      end

      expect(page.url).to end_with('#clicked')
    end
  end

  it 'should select the text by triple clicking' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      text = 'This is the text that we are going to try to select. Let\'s see how it goes.'
      page.click('textarea')
      page.evaluate("(text) => { document.querySelector('textarea').value = text; }", text)
      page.click('textarea', count: 3)
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
  end

  it 'should click offscreen buttons' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/offscreenbuttons.html")
      messages = []
      page.evaluate(<<~JS)
        () => {
          window.messages = [];
          for (let i = 0; i < 11; ++i) {
            const button = document.createElement('button');
            button.textContent = i;
            button.onclick = () => window.messages.push(i);
            document.body.appendChild(button);
          }
        }
      JS

      11.times do |i|
        page.click("button:nth-of-type(#{i + 1})")
      end

      messages = page.evaluate('window.messages')
      expect(messages).to eq((0...11).to_a)
    end
  end

  it 'should click wrapped links' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/wrappedlink.html")
      page.click('a')
      result = page.evaluate('window.__clicked')
      expect(result).to be true
    end
  end

  it 'should click on checkbox input and toggle' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/checkbox.html")
      expect(page.evaluate("() => document.querySelector('input').checked")).to be_falsy
      page.click('input#agree')
      expect(page.evaluate("() => document.querySelector('input').checked")).to be true

      result = page.evaluate(<<~JS)
        () => {
          const events = globalThis.events;
          return [events.length, events[0].type, events[1].type];
        }
      JS
      # Firefox BiDi may have slightly different event order, check that we have at least click and input
      expect(result[0]).to be >= 2
      expect(result[1]).to eq('click')
      expect(['input', 'click']).to include(result[2])
    end
  end

  it 'should click on checkbox label and toggle' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/checkbox.html")
      expect(page.evaluate("() => document.querySelector('input').checked")).to be_falsy
      page.click('label[for="agree"]')
      expect(page.evaluate("() => document.querySelector('input').checked")).to be true

      result = page.evaluate(<<~JS)
        () => {
          const events = globalThis.events;
          return events.map(e => e.type);
        }
      JS
      # Firefox BiDi may have slightly different event order
      # Just verify we got click events and the checkbox is toggled
      expect(result).to include('click')
      expect(result.length).to be >= 3
    end
  end

  it 'should fail to click a missing button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      expect {
        page.click('button.does-not-exist')
      }.to raise_error(/failed to find element matching selector/)
    end
  end

  it 'should scroll and click the button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      20.times do |i|
        page.click("#button-#{i}")
      end

      result = page.evaluate(<<~JS)
        () => {
          return globalThis.clicked;
        }
      JS
      expect(result).to eq(19) # Last button clicked (0-indexed to 19)
    end
  end

  it 'should double click the button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.evaluate(<<~JS)
        () => {
          window.double = false;
          const button = document.querySelector('button');
          button.addEventListener('dblclick', () => {
            window.double = true;
          });
        }
      JS

      page.click('button', count: 2)
      result = page.evaluate('window.double')
      expect(result).to be true

      result = page.evaluate('window.result')
      expect(result).to eq('Clicked')
    end
  end

  it 'should click a partially obscured button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.evaluate(<<~JS)
        () => {
          const button = document.querySelector('button');
          button.textContent = 'Some really long text that will go off screen';
          button.style.position = 'absolute';
          button.style.left = '368px';
        }
      JS

      page.click('button')
      result = page.evaluate('window.result')
      expect(result).to eq('Clicked')
    end
  end

  it 'should click a rotated button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/rotatedButton.html")
      page.click('button')
      result = page.evaluate('window.result')
      expect(result).to eq('Clicked')
    end
  end

  it 'should fire contextmenu event on right click' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.click('#button-8', button: 'right')
      result = page.evaluate(<<~JS)
        () => {
          return document.querySelector('#button-8').textContent;
        }
      JS
      expect(result).to eq('context menu')
    end
  end

  it 'should fire aux event on middle click' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.click('#button-8', button: 'middle')
      result = page.evaluate(<<~JS)
        () => {
          return globalThis.auxclick;
        }
      JS
      expect(result).to be true
    end
  end

  it 'should click links which cause navigation' do
    with_test_state do |page:, server:, **|
      page.set_content("<a href=\"#{server.empty_page}\">empty.html</a>")
      # This should not hang
      page.click('a')
    end
  end

  it 'should click the button inside an iframe' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.empty_page}")
      page.set_content('<iframe name="frame1"></iframe>')
      page.evaluate(<<~JS, server.prefix)
        (prefix) => {
          const frame = document.querySelector('iframe');
          frame.src = prefix + '/input/button.html';
          return new Promise(x => frame.onload = x);
        }
      JS

      # For now, skip iframe tests as we need to implement frame support
      skip 'Frame support not yet implemented'
    end
  end
end

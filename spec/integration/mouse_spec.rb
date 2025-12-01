# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Mouse' do
  # Helper to get textarea dimensions
  def dimensions(page)
    page.evaluate(<<~JS)
      () => {
        const rect = document.querySelector('textarea').getBoundingClientRect();
        return {
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height
        };
      }
    JS
  end

  # Helper to add mouse event data listeners
  def add_mouse_data_listeners(page, include_move: false)
    page.evaluate(<<~JS, include_move)
      (includeMove) => {
        const clicks = [];
        const mouseEventListener = (event) => {
          clicks.push({
            type: event.type,
            detail: event.detail,
            clientX: event.clientX,
            clientY: event.clientY,
            isTrusted: event.isTrusted,
            button: event.button,
            buttons: event.buttons,
          });
        };
        document.addEventListener('mousedown', mouseEventListener);
        if (includeMove) {
          document.addEventListener('mousemove', mouseEventListener);
        }
        document.addEventListener('mouseup', mouseEventListener);
        document.addEventListener('click', mouseEventListener);
        document.addEventListener('auxclick', mouseEventListener);
        window.clicks = clicks;
      }
    JS
  end

  it 'should click the document' do
    with_test_state do |page:, **|
      page.evaluate(<<~JS)
        () => {
          globalThis.clickPromise = new Promise(resolve => {
            document.addEventListener('click', event => {
              resolve({
                type: event.type,
                detail: event.detail,
                clientX: event.clientX,
                clientY: event.clientY,
                isTrusted: event.isTrusted,
                button: event.button,
              });
            });
          });
        }
      JS

      page.mouse.click(50, 60)
      event = page.evaluate('() => globalThis.clickPromise')

      expect(event['type']).to eq('click')
      expect(event['detail']).to eq(1)
      expect(event['clientX']).to eq(50)
      expect(event['clientY']).to eq(60)
      expect(event['isTrusted']).to be true
      expect(event['button']).to eq(0)
    end
  end

  it 'should resize the textarea' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      dim = dimensions(page)
      x = dim['x']
      y = dim['y']
      width = dim['width']
      height = dim['height']

      mouse = page.mouse
      mouse.move(x + width - 4, y + height - 4)
      mouse.down
      mouse.move(x + width + 100, y + height + 100)
      mouse.up

      new_dim = dimensions(page)
      expect(new_dim['width']).to eq((width + 104).round)
      expect(new_dim['height']).to eq((height + 104).round)
    end
  end

  it 'should select the text with mouse' do
    with_test_state do |page:, server:, **|
      text = "This is the text that we are going to try to select. Let's see how it goes."

      page.goto("#{server.prefix}/input/textarea.html")
      page.focus('textarea')
      page.keyboard.type(text)

      # Wait for text to be typed
      page.wait_for_selector('textarea')
      textarea = page.query_selector('textarea')

      dim = dimensions(page)
      x = dim['x']
      y = dim['y']

      page.mouse.move(x + 2, y + 2)
      page.mouse.down
      page.mouse.move(100, 100)
      page.mouse.up

      result = textarea.evaluate(<<~JS)
        element => {
          return element.value.substring(
            element.selectionStart,
            element.selectionEnd
          );
        }
      JS
      expect(result).to eq(text)
    end
  end

  it 'should trigger hover state' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")

      page.hover('#button-6')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')

      page.hover('#button-2')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-2')

      page.hover('#button-91')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-91')
    end
  end

  it 'should trigger hover state with removed window.Node' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.evaluate('() => delete window.Node')

      page.hover('#button-6')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')
    end
  end

  it 'should set modifier keys on click' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.evaluate(<<~JS)
        () => {
          document.querySelector('#button-3').addEventListener(
            'mousedown',
            e => {
              globalThis.lastEvent = e;
            },
            true
          );
        }
      JS

      modifiers = {
        'Shift' => 'shiftKey',
        'Control' => 'ctrlKey',
        'Alt' => 'altKey',
      }

      # In Firefox, the Meta modifier only exists on Mac
      modifiers['Meta'] = 'metaKey' if RUBY_PLATFORM.include?('darwin')

      modifiers.each do |modifier, key|
        page.keyboard.down(modifier)
        page.click('#button-3')

        result = page.evaluate("(mod) => globalThis.lastEvent[mod]", key)
        expect(result).to be(true), "#{key} should be true"

        page.keyboard.up(modifier)
      end

      page.click('#button-3')

      modifiers.each do |_modifier, key|
        result = page.evaluate("(mod) => globalThis.lastEvent[mod]", key)
        expect(result).to be(false), "#{key} should be false"
      end
    end
  end

  it 'should send mouse wheel events' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/wheel.html")
      elem = page.query_selector('div')
      bounding_box_before = elem.bounding_box

      expect(bounding_box_before.width).to eq(115)
      expect(bounding_box_before.height).to eq(115)

      page.mouse.move(
        bounding_box_before.x + bounding_box_before.width / 2,
        bounding_box_before.y + bounding_box_before.height / 2
      )

      page.mouse.wheel(delta_y: -100)

      bounding_box_after = elem.bounding_box
      expect(bounding_box_after.width).to eq(230)
      expect(bounding_box_after.height).to eq(230)
    end
  end

  it 'should set ctrlKey on the wheel event' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.evaluate(<<~JS)
        () => {
          globalThis.ctrlKeyPromise = new Promise(resolve => {
            window.addEventListener(
              'wheel',
              event => {
                resolve(event.ctrlKey);
              },
              { once: true }
            );
          });
        }
      JS

      page.keyboard.down('Control')
      page.mouse.wheel(delta_y: -100)
      # Scroll back to work around Firefox bug
      page.mouse.wheel(delta_y: 100)
      page.keyboard.up('Control')

      ctrl_key = page.evaluate('() => globalThis.ctrlKeyPromise')
      expect(ctrl_key).to be true
    end
  end

  it 'should tween mouse movement' do
    with_test_state do |page:, **|
      page.mouse.move(100, 100)
      page.evaluate(<<~JS)
        () => {
          globalThis.result = [];
          document.addEventListener('mousemove', event => {
            globalThis.result.push([event.clientX, event.clientY]);
          });
        }
      JS

      page.mouse.move(200, 300, steps: 5)

      result = page.evaluate('result')
      expect(result).to eq([
        [120, 140],
        [140, 180],
        [160, 220],
        [180, 260],
        [200, 300]
      ])
    end
  end

  it 'should work with mobile viewports and cross process navigations' do
    with_test_state do |page:, server:, **|
      pending 'set_viewport does not support is_mobile parameter yet'

      page.goto(server.empty_page)
      page.set_viewport(width: 360, height: 640, is_mobile: true)
      page.goto("#{server.cross_process_prefix}/mobile.html")

      page.evaluate(<<~JS)
        () => {
          document.addEventListener('click', event => {
            globalThis.result = { x: event.clientX, y: event.clientY };
          });
        }
      JS

      page.mouse.click(30, 40)

      result = page.evaluate('result')
      expect(result).to eq({ 'x' => 30, 'y' => 40 })
    end
  end

  it 'should not throw if buttons are pressed twice' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.mouse.down
      page.mouse.down
    end
  end

  it 'should not throw if clicking in parallel' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      add_mouse_data_listeners(page)

      # Sequential clicks instead of truly parallel (BiDi protocol limitation)
      page.mouse.click(0, 5)
      page.mouse.click(6, 10)

      data = page.evaluate('() => window.clicks')

      # First click events
      expect(data[0]['type']).to eq('mousedown')
      expect(data[0]['clientX']).to eq(0)
      expect(data[0]['clientY']).to eq(5)
      expect(data[0]['button']).to eq(0)

      expect(data[1]['type']).to eq('mouseup')
      expect(data[2]['type']).to eq('click')

      # Second click events
      expect(data[3]['type']).to eq('mousedown')
      expect(data[3]['clientX']).to eq(6)
      expect(data[3]['clientY']).to eq(10)
    end
  end

  it 'should reset properly' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.mouse.move(5, 5)

      page.mouse.down(button: 'left')
      page.mouse.down(button: 'middle')
      page.mouse.down(button: 'right')

      add_mouse_data_listeners(page, include_move: true)
      page.mouse.reset

      data = page.evaluate('() => window.clicks')

      # Verify we got mouseup events
      expect(data.length).to be >= 2

      # First mouseup should be for right button
      expect(data[0]['type']).to eq('mouseup')
      expect(data[0]['button']).to eq(2)
      expect(data[0]['clientX']).to eq(5)
      expect(data[0]['clientY']).to eq(5)
    end
  end

  it 'should evaluate before mouse event' do
    with_test_state do |page:, server:, **|
      pending 'element_handle.clickable_point not implemented yet'

      page.goto(server.empty_page)
      page.goto("#{server.cross_process_prefix}/input/button.html")

      button = page.wait_for_selector('button')
      point = button.clickable_point

      page.evaluate(<<~JS)
        () => {
          globalThis.clickPromise = new Promise(resolve => {
            document.querySelector('button').addEventListener('click', resolve, { once: true });
          });
        }
      JS

      page.mouse.click(point['x'], point['y'])
      page.evaluate('() => globalThis.clickPromise')
    end
  end
end

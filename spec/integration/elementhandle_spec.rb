# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ElementHandle specs' do
  describe 'ElementHandle.boundingBox' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/grid.html")
        element_handle = page.query_selector('.box:nth-of-type(13)')
        box = element_handle.bounding_box
        expect(box.x).to eq(100)
        expect(box.y).to eq(50)
        expect(box.width).to eq(50)
        expect(box.height).to eq(50)
      end
    end

    it 'should handle nested frames' do
      with_test_state do |page:, server:, **|
        skip 'Nested frames not yet implemented'

        page.set_viewport(width: 500, height: 500)
        page.goto("#{server.prefix}/frames/nested-frames.html")
        nested_frame = page.frames[1].child_frames[1]
        element_handle = nested_frame.query_selector('div')
        box = element_handle.bounding_box
        expect(box.x).to eq(28)
        expect(box.y).to eq(182)
        expect(box.width).to eq(300)
        expect(box.height).to eq(18)
      end
    end

    it 'should return null for invisible elements' do
      with_test_state do |page:, **|
        page.set_content('<div style="display:none">hi</div>')
        element = page.query_selector('div')
        expect(element.bounding_box).to be_nil
      end
    end

    it 'should force a layout' do
      with_test_state do |page:, **|
        page.set_viewport(width: 500, height: 500)
        page.set_content('<div style="width: 100px; height: 100px">hello</div>')
        element_handle = page.query_selector('div')
        element_handle.evaluate("element => element.style.height = '200px'")
        box = element_handle.bounding_box
        expect(box.x).to eq(8)
        expect(box.y).to eq(8)
        expect(box.width).to eq(100)
        expect(box.height).to eq(200)
      end
    end

    it 'should work with SVG nodes' do
      with_test_state do |page:, **|
        page.set_content(<<~HTML)
          <svg xmlns="http://www.w3.org/2000/svg" width="500" height="500">
            <rect id="theRect" x="30" y="50" width="200" height="300"></rect>
          </svg>
        HTML

        element = page.query_selector('#theRect')
        pptr_bounding_box = element.bounding_box
        web_bounding_box = page.evaluate(<<~JS)
          () => {
            const e = document.querySelector('#theRect');
            const rect = e.getBoundingClientRect();
            return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
          }
        JS
        expect(pptr_bounding_box.x).to eq(web_bounding_box['x'])
        expect(pptr_bounding_box.y).to eq(web_bounding_box['y'])
        expect(pptr_bounding_box.width).to eq(web_bounding_box['width'])
        expect(pptr_bounding_box.height).to eq(web_bounding_box['height'])
      end
    end
  end

  describe 'ElementHandle.boxModel' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        # This test requires frame offset handling which is not yet implemented
        skip 'Frame offset handling not yet implemented'

        page.goto("#{server.prefix}/resetcss.html")

        # Step 1: Add Frame and position it absolutely
        page.evaluate(<<~JS, server.prefix)
          (prefix) => {
            const frame = document.createElement('iframe');
            frame.id = 'frame1';
            frame.src = prefix + '/resetcss.html';
            document.body.appendChild(frame);
            return new Promise(resolve => frame.onload = resolve);
          }
        JS
        page.evaluate(<<~JS)
          () => {
            const frame = document.querySelector('#frame1');
            frame.style.position = 'absolute';
            frame.style.left = '1px';
            frame.style.top = '2px';
          }
        JS

        # Step 2: Add div and position it absolutely inside frame
        frame = page.frames[1]
        div_handle = frame.evaluate_handle(<<~JS).as_element
          () => {
            const div = document.createElement('div');
            document.body.appendChild(div);
            div.style.boxSizing = 'border-box';
            div.style.position = 'absolute';
            div.style.borderLeft = '1px solid black';
            div.style.paddingLeft = '2px';
            div.style.marginLeft = '3px';
            div.style.left = '4px';
            div.style.top = '5px';
            div.style.width = '6px';
            div.style.height = '7px';
            return div;
          }
        JS

        # Step 3: query div's boxModel and assert box values
        box = div_handle.box_model
        expect(box.width).to eq(6)
        expect(box.height).to eq(7)
        # Note: These would need Point comparison when frame offset is implemented
        expect(box.margin[0].x).to eq(1 + 4) # frame.left + div.left
        expect(box.margin[0].y).to eq(2 + 5)
        expect(box.border[0].x).to eq(1 + 4 + 3) # frame.left + div.left + div.margin-left
        expect(box.border[0].y).to eq(2 + 5)
        expect(box.padding[0].x).to eq(1 + 4 + 3 + 1) # + div.borderLeft
        expect(box.padding[0].y).to eq(2 + 5)
        expect(box.content[0].x).to eq(1 + 4 + 3 + 1 + 2) # + div.paddingLeft
        expect(box.content[0].y).to eq(2 + 5)
      end
    end

    it 'should return null for invisible elements' do
      with_test_state do |page:, **|
        page.set_content('<div style="display:none">hi</div>')
        element = page.query_selector('div')
        expect(element.box_model).to be_nil
      end
    end

    it 'should correctly compute box model with offsets' do
      with_test_state do |page:, **|
        border = 10
        padding = 11
        margin = 12
        width = 200
        height = 100
        vertical_offset = 100
        horizontal_offset = 100

        page.set_content(<<~HTML)
          <div style="position:absolute; left: #{horizontal_offset}px; top: #{vertical_offset}px; width: #{width}px; height: #{height}px; border: #{border}px solid green; padding: #{padding}px; margin: #{margin}px;" id="box"></div>
        HTML

        element = page.query_selector('#box')
        box_model = element.box_model

        expect(box_model.width).to eq(width + padding * 2 + border * 2)
        expect(box_model.height).to eq(height + padding * 2 + border * 2)
      end
    end
  end

  describe 'ElementHandle.contentFrame' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate(<<~JS, server.empty_page)
          (url) => {
            const frame = document.createElement('iframe');
            frame.id = 'frame1';
            frame.src = url;
            document.body.appendChild(frame);
            return new Promise(resolve => frame.onload = resolve);
          }
        JS
        element_handle = page.query_selector('#frame1')
        frame = element_handle.content_frame
        # Compare browsing context IDs since Frame instances may differ
        expect(frame.browsing_context.id).to eq(page.frames[1].browsing_context.id)
      end
    end
  end

  describe 'ElementHandle.isVisible and ElementHandle.isHidden' do
    it 'should work' do
      with_test_state do |page:, **|
        page.set_content('<div style="display: none">text</div>')
        element = page.wait_for_selector('div')
        expect(element.visible?).to be false
        expect(element.hidden?).to be true
        element.evaluate("e => e.style.removeProperty('display')")
        expect(element.visible?).to be true
        expect(element.hidden?).to be false
      end
    end
  end

  describe 'ElementHandle.click' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/button.html")
        button = page.query_selector('button')
        button.click
        expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
      end
    end

    it 'should return Point data' do
      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            document.body.style.padding = '0';
            document.body.style.margin = '0';
            document.body.innerHTML = `
              <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
            `;
            window.clicks = [];
            document.body.addEventListener('click', e => {
              window.clicks.push([e.clientX, e.clientY]);
            });
          }
        JS

        div_handle = page.query_selector('div')
        div_handle.click
        div_handle.click(offset: { x: 10, y: 15 })

        # Wait for clicks to be recorded
        clicks = page.evaluate('() => window.clicks')
        expect(clicks).to eq([
          [45 + 60, 45 + 30], # margin + middle point offset
          [30 + 10, 30 + 15]  # margin + offset
        ])
      end
    end

    it 'should work for Shadow DOM v1' do
      with_test_state do |page:, server:, **|
        pending 'shadow.html test asset not available'

        page.goto("#{server.prefix}/shadow.html")
        button_handle = page.evaluate_handle('() => button')
        button_handle.click
        expect(page.evaluate('() => clicked')).to be true
      end
    end

    it 'should not work for TextNodes' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/button.html")
        button_text_node = page.evaluate_handle(<<~JS)
          () => document.querySelector('button').firstChild
        JS
        # TextNodes are not valid targets for IntersectionObserver or click operations
        expect {
          button_text_node.click
        }.to raise_error(RuntimeError)
      end
    end

    it 'should throw for detached nodes' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/button.html")
        button = page.query_selector('button')
        page.evaluate('button => button.remove()', button)
        expect {
          button.click
        }.to raise_error(/Node is detached from document|no such node|Node is either not clickable/)
      end
    end

    it 'should throw for hidden nodes' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/button.html")
        button = page.query_selector('button')
        page.evaluate("button => button.style.display = 'none'", button)
        expect {
          button.click
        }.to raise_error(/Node is either not clickable or not an Element|no such element/)
      end
    end

    it 'should throw for recursively hidden nodes' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/button.html")
        button = page.query_selector('button')
        page.evaluate("button => button.parentElement.style.display = 'none'", button)
        expect {
          button.click
        }.to raise_error(/Node is either not clickable or not an Element|no such element/)
      end
    end

    it 'should throw for <br> elements' do
      with_test_state do |page:, **|
        page.set_content('hello<br />goodbye')
        br = page.query_selector('br')
        expect {
          br.click
        }.to raise_error(/Node is either not clickable or not an Element|no such node/)
      end
    end
  end

  describe 'ElementHandle.touchStart' do
    it 'should work' do
      with_test_state do |page:, **|
        pending 'touchStart not yet implemented'

        page.evaluate(<<~JS)
          () => {
            document.body.style.padding = '0';
            document.body.style.margin = '0';
            document.body.innerHTML = `
              <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
            `;
            window.events = [];
            document.addEventListener('touchstart', (e) => {
              window.events.push({
                changed: [...e.changedTouches].map(t => [t.clientX, t.clientY]),
                touches: [...e.touches].map(t => [t.clientX, t.clientY])
              });
            });
          }
        JS

        div_handle = page.query_selector('div')
        div_handle.touch_start

        events = page.evaluate('() => window.events')
        expected_touch_location = [45 + 60, 45 + 30] # margin + middle point offset
        expect(events).to eq([
          {
            'changed' => [expected_touch_location],
            'touches' => [expected_touch_location]
          }
        ])
      end
    end
  end

  describe 'ElementHandle.touchMove' do
    it 'should work' do
      with_test_state do |page:, **|
        pending 'touchMove not yet implemented'

        page.evaluate(<<~JS)
          () => {
            document.body.style.padding = '0';
            document.body.style.margin = '0';
            document.body.innerHTML = `
              <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
            `;
            window.events = [];
            const handler = (e) => {
              window.events.push({
                changed: [...e.changedTouches].map(t => [t.clientX, t.clientY]),
                touches: [...e.touches].map(t => [t.clientX, t.clientY])
              });
            };
            document.addEventListener('touchstart', handler);
            document.addEventListener('touchmove', handler);
          }
        JS

        div_handle = page.query_selector('div')
        page.touchscreen.touch_start(200, 200)
        div_handle.touch_move

        events = page.evaluate('() => window.events')
        expected_div_touch_location = [45 + 60, 45 + 30] # margin + middle point offset
        expect(events).to eq([
          {
            'changed' => [[200, 200]],
            'touches' => [[200, 200]]
          },
          {
            'changed' => [expected_div_touch_location],
            'touches' => [expected_div_touch_location]
          }
        ])
      end
    end
  end

  describe 'ElementHandle.touchEnd' do
    it 'should work' do
      with_test_state do |page:, **|
        pending 'touchEnd not yet implemented'

        page.evaluate(<<~JS)
          () => {
            document.body.style.padding = '0';
            document.body.style.margin = '0';
            document.body.innerHTML = `
              <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
            `;
            window.events = [];
            const handler = (e) => {
              window.events.push({
                changed: [...e.changedTouches].map(t => [t.clientX, t.clientY]),
                touches: [...e.touches].map(t => [t.clientX, t.clientY])
              });
            };
            document.addEventListener('touchstart', handler);
            document.addEventListener('touchend', handler);
          }
        JS

        div_handle = page.query_selector('div')
        page.touchscreen.touch_start(100, 100)
        div_handle.touch_end

        events = page.evaluate('() => window.events')
        expect(events).to eq([
          {
            'changed' => [[100, 100]],
            'touches' => [[100, 100]]
          },
          {
            'changed' => [[100, 100]],
            'touches' => []
          }
        ])
      end
    end
  end

  describe 'ElementHandle.clickablePoint' do
    it 'should work' do
      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            document.body.style.padding = '0';
            document.body.style.margin = '0';
            document.body.innerHTML = `
              <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
            `;
          }
        JS
        page.evaluate('() => new Promise(resolve => window.requestAnimationFrame(resolve))')
        div_handle = page.query_selector('div')

        point = div_handle.clickable_point
        expect(point.x).to eq(45 + 60) # margin + middle point offset
        expect(point.y).to eq(45 + 30) # margin + middle point offset

        point_with_offset = div_handle.clickable_point(offset: { x: 10, y: 15 })
        expect(point_with_offset.x).to eq(30 + 10) # margin + offset
        expect(point_with_offset.y).to eq(30 + 15) # margin + offset
      end
    end

    it 'should not work if the click box is not visible' do
      with_test_state do |page:, **|
        page.set_content('<button style="width: 10px; height: 10px; position: absolute; left: -20px"></button>')
        handle = page.query_selector('button')
        expect { handle.clickable_point }.to raise_error(RuntimeError)

        page.set_content('<button style="width: 10px; height: 10px; position: absolute; right: -20px"></button>')
        handle2 = page.query_selector('button')
        expect { handle2.clickable_point }.to raise_error(RuntimeError)

        page.set_content('<button style="width: 10px; height: 10px; position: absolute; top: -20px"></button>')
        handle3 = page.query_selector('button')
        expect { handle3.clickable_point }.to raise_error(RuntimeError)

        page.set_content('<button style="width: 10px; height: 10px; position: absolute; bottom: -20px"></button>')
        handle4 = page.query_selector('button')
        expect { handle4.clickable_point }.to raise_error(RuntimeError)
      end
    end

    it 'should work for iframes' do
      with_test_state do |page:, **|
        skip 'Frame support not yet fully implemented'

        page.evaluate(<<~JS)
          () => {
            document.body.style.padding = '10px';
            document.body.style.margin = '10px';
            document.body.innerHTML = `
              <iframe style="border: none; margin: 0; padding: 0;" seamless sandbox srcdoc="<style>* { margin: 0; padding: 0;}</style><div style='cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;' />"></iframe>
            `;
          }
        JS
        page.evaluate('() => new Promise(resolve => window.requestAnimationFrame(resolve))')
        frame = page.frames[1]
        div_handle = frame.query_selector('div')

        point = div_handle.clickable_point
        expect(point.x).to eq(20 + 45 + 60) # iframe pos + margin + middle point offset
        expect(point.y).to eq(20 + 45 + 30) # iframe pos + margin + middle point offset

        point_with_offset = div_handle.clickable_point(offset: { x: 10, y: 15 })
        expect(point_with_offset.x).to eq(20 + 30 + 10) # iframe pos + margin + offset
        expect(point_with_offset.y).to eq(20 + 30 + 15) # iframe pos + margin + offset
      end
    end
  end

  describe 'Element.waitForSelector' do
    it 'should wait correctly with waitForSelector on an element' do
      with_test_state do |page:, **|
        # Wait for the element to appear while setting content in the block
        element = page.wait_for_selector('.foo') do
          page.set_content(<<~HTML)
            <div id="not-foo"></div>
            <div class="bar">bar2</div>
            <div class="foo">Foo1</div>
          HTML
        end
        expect(element).not_to be_nil

        # Wait for a nested selector while setting inner content in the block
        element2 = element.wait_for_selector('.bar') do
          element.evaluate("el => el.innerHTML = '<div class=\"bar\">bar1</div>'")
        end
        expect(element2).not_to be_nil
        expect(element2.evaluate('el => el.innerText')).to eq('bar1')
      end
    end

    it 'should wait correctly with waitForSelector and xpath on an element' do
      with_test_state do |page:, **|
        page.set_content(<<~HTML)
          <div id="el1">
            el1
            <div id="el2">el2</div>
          </div>
          <div id="el3">el3</div>
        HTML

        el_by_id = page.wait_for_selector('#el1')
        el_by_xpath = el_by_id.wait_for_selector('xpath/.//div')
        expect(el_by_xpath.evaluate('el => el.id')).to eq('el2')
      end
    end
  end

  describe 'ElementHandle.hover' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/scrollable.html")
        button = page.query_selector('#button-6')
        button.hover
        expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')
      end
    end
  end

  describe 'ElementHandle.isIntersectingViewport' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/offscreenbuttons.html")

        button_visibility = (0..10).map do |i|
          button = page.query_selector("#btn#{i}")
          button.intersecting_viewport?
        end

        (0..10).each do |i|
          # All but last button are visible
          visible = i < 10
          expect(button_visibility[i]).to eq(visible), "Button #btn#{i} visibility should be #{visible}"
        end
      end
    end

    it 'should work with threshold' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/offscreenbuttons.html")
        # a button almost cannot be seen
        button = page.query_selector('#btn11')
        expect(button.intersecting_viewport?(threshold: 0.001)).to be false
      end
    end

    it 'should work with threshold of 1' do
      with_test_state do |page:, server:, **|
        # Implementation uses > instead of >= for threshold comparison
        # This causes threshold: 1 to fail when intersectionRatio is exactly 1.0
        pending 'Implementation needs to use >= instead of > for threshold comparison'

        page.goto("#{server.prefix}/offscreenbuttons.html")
        button = page.query_selector('#btn0')
        expect(button.intersecting_viewport?(threshold: 1)).to be true
      end
    end

    it 'should work with svg elements' do
      with_test_state do |page:, server:, **|
        pending 'inline-svg.html test asset not available'

        page.goto("#{server.prefix}/inline-svg.html")
        visible_circle = page.query_selector('circle')
        visible_svg = page.query_selector('svg')

        expect(visible_circle.intersecting_viewport?(threshold: 1)).to be true
        expect(visible_circle.intersecting_viewport?(threshold: 0)).to be true
        expect(visible_svg.intersecting_viewport?(threshold: 1)).to be true
        expect(visible_svg.intersecting_viewport?(threshold: 0)).to be true

        invisible_circle = page.query_selector('div circle')
        invisible_svg = page.query_selector('div svg')

        expect(invisible_circle.intersecting_viewport?(threshold: 1)).to be false
        expect(invisible_circle.intersecting_viewport?(threshold: 0)).to be false
        expect(invisible_svg.intersecting_viewport?(threshold: 1)).to be false
        expect(invisible_svg.intersecting_viewport?(threshold: 0)).to be false
      end
    end
  end

  describe 'Custom queries' do
    it 'should register and unregister' do
      with_test_state do |page:, **|
        pending 'Custom query handlers not yet fully implemented'

        page.set_content('<div id="not-foo"></div><div id="foo"></div>')

        # Register
        Puppeteer::Bidi.register_custom_query_handler('getById') do |_element, selector|
          # queryOne implementation
          "document.querySelector('[id=\"#{selector}\"]')"
        end

        element = page.query_selector('getById/foo')
        expect(page.evaluate('element => element.id', element)).to eq('foo')

        handler_names = Puppeteer::Bidi.custom_query_handler_names
        expect(handler_names).to include('getById')

        # Unregister
        Puppeteer::Bidi.unregister_custom_query_handler('getById')
        expect {
          page.query_selector('getById/foo')
        }.to raise_error
      end
    end

    it 'should throw with invalid query names' do
      with_test_state do |**|
        pending 'Custom query handlers not yet fully implemented'

        expect {
          Puppeteer::Bidi.register_custom_query_handler('1/2/3') { 'foo' }
        }.to raise_error(/Custom query handler names may only contain/)
      end
    end

    it 'should work for multiple elements' do
      with_test_state do |page:, **|
        pending 'Custom query handlers not yet fully implemented'

        page.set_content(<<~HTML)
          <div id="not-foo"></div>
          <div class="foo">Foo1</div>
          <div class="foo baz">Foo2</div>
        HTML

        Puppeteer::Bidi.register_custom_query_handler('getByClass',
          query_all: proc { |_element, selector| "[...document.querySelectorAll('.#{selector}')]" }
        )

        elements = page.query_selector_all('getByClass/foo')
        class_names = elements.map { |el| page.evaluate('element => element.className', el) }
        expect(class_names).to eq(['foo', 'foo baz'])
      end
    end
  end

  describe 'ElementHandle.toElement' do
    it 'should work' do
      with_test_state do |page:, **|
        page.set_content('<div class="foo">Foo1</div>')
        element = page.query_selector('.foo')
        div = element.to_element('div')
        expect(div).not_to be_nil
        expect(div).to eq(element)
      end
    end

    it 'should throw if element does not match' do
      with_test_state do |page:, **|
        page.set_content('<div class="foo">Foo1</div>')
        element = page.query_selector('.foo')
        expect {
          element.to_element('span')
        }.to raise_error(/Element is not a\(n\) `span` element/)
      end
    end
  end

  describe 'ElementHandle.dispose' do
    it 'should dispose the element handle' do
      with_test_state do |page:, **|
        page.set_content('<button>Click me!</button>')
        button = page.wait_for_selector('button')
        expect(button.disposed?).to be false
        button.dispose
        expect(button.disposed?).to be true
      end
    end
  end
end

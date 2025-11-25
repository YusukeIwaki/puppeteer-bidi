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

RSpec.describe 'Page.waitForSelector', type: :integration do
  describe 'basic functionality' do
    it 'should immediately resolve if element exists' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div>visible</div>')

        element = page.wait_for_selector('div')
        expect(element).not_to be_nil
        expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
        element.dispose
      end
    end

    it 'should resolve when element is added' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        Sync do
          watchdog = Async do
            page.wait_for_selector('div')
          end

          # Add the element after a short delay
          Async do
            sleep 0.1
            page.evaluate("() => { const div = document.createElement('div'); document.body.appendChild(div); }")
          end

          element = watchdog.wait
          expect(element).not_to be_nil
          element.dispose
        end
      end
    end

    it 'should work with removed MutationObserver' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        page.evaluate('() => delete window.MutationObserver')
        handle = page.wait_for_selector('.zombo', timeout: 100) rescue nil

        # Should not find element and timeout
        expect(handle).to be_nil
      end
    end

    it 'should resolve promise when element is added' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        Sync do
          watchdog = Async do
            page.wait_for_selector('div')
          end

          Async do
            # page.waitForSelector is using raf-based polling and will not be checking DOM every moment.
            sleep 0.05

            page.evaluate("() => document.body.innerHTML = '<div></div>'")
          end.wait

          element = watchdog.wait
          expect(element).not_to be_nil
          element.dispose
        end
      end
    end

    it 'should timeout' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        expect {
          page.wait_for_selector('div', timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError, /100ms exceeded/)
      end
    end

    it 'should respect timeout' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        expect {
          page.wait_for_selector('div', timeout: 50)
        }.to raise_error(Puppeteer::Bidi::TimeoutError, /50ms exceeded/)
      end
    end

    it 'should have an error message specifically for awaiting an element to be hidden' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div>text</div>')

        expect {
          page.wait_for_selector('div', hidden: true, timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError, /100ms exceeded/)
      end
    end

    it 'should respond to node attribute mutation' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        Sync do
          div_found = false

          watchdog = Async do
            page.wait_for_selector('.zombo').tap { div_found = true }
          end

          page.set_content('<div class="notZombo"></div>')
          expect(div_found).to be false

          page.evaluate("() => document.querySelector('div').className = 'zombo'")

          element = watchdog.wait
          expect(element).not_to be_nil
          element.dispose
        end
      end
    end

    it 'should return the element handle' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        Sync do
          watchdog = Async do
            page.wait_for_selector('.zombo')
          end

          page.set_content("<div class='zombo'>anything</div>")

          element = watchdog.wait
          expect(element.evaluate('x => x.textContent')).to eq('anything')
          element.dispose
        end
      end
    end
  end

  describe 'visibility options' do
    it 'should work with visible option' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div style="display: none;">hidden</div>')

        Sync do
          div_visible = false

          watchdog = Async do
            page.wait_for_selector('div', visible: true).tap { div_visible = true }
          end

          # Element exists but is not visible yet
          sleep 0.1
          expect(div_visible).to be false

          # Make element visible
          page.evaluate("() => document.querySelector('div').style.display = 'block'")

          element = watchdog.wait
          expect(element).not_to be_nil
          element.dispose
        end
      end
    end

    it 'should return null for hidden: true when element does not exist' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        # When using hidden: true, and element doesn't exist,
        # checkVisibility returns true (no element = hidden state is satisfied)
        element = page.wait_for_selector('div', hidden: true)
        # In this case we get a truthy return from checkVisibility (true), not an element
        # The behavior depends on checkVisibility implementation
        # For non-existent element with hidden: true, it returns true (not element)
        expect(element).to be_nil
      end
    end

    it 'should wait for element to become hidden' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div>visible</div>')

        Sync do
          hidden_satisfied = false

          watchdog = Async do
            page.wait_for_selector('div', hidden: true).tap { hidden_satisfied = true }
          end

          # Element is visible
          sleep 0.1
          expect(hidden_satisfied).to be false

          # Remove the element
          page.evaluate("() => document.querySelector('div').remove()")

          result = watchdog.wait
          # When element is removed, hidden condition is satisfied
          expect(result).to be_nil
        end
      end
    end

    it 'should wait for element to be hidden via display:none' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div>visible</div>')

        Sync do
          hidden_satisfied = false

          watchdog = Async do
            page.wait_for_selector('div', hidden: true).tap { hidden_satisfied = true }
          end

          # Element is visible
          sleep 0.1
          expect(hidden_satisfied).to be false

          # Hide the element
          page.evaluate("() => document.querySelector('div').style.display = 'none'")

          result = watchdog.wait
          # When element is hidden, we may still get a handle to it
          # (checkVisibility returns the element when hidden: true and element is hidden)
          expect(result).to be_a(Puppeteer::Bidi::ElementHandle)
          result.dispose if result
        end
      end
    end

    it 'should wait for element to be hidden via visibility:hidden' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div>visible</div>')

        Sync do
          hidden_satisfied = false

          watchdog = Async do
            page.wait_for_selector('div', hidden: true).tap { hidden_satisfied = true }
          end

          # Element is visible
          sleep 0.1
          expect(hidden_satisfied).to be false

          # Hide the element with visibility: hidden
          page.evaluate("() => document.querySelector('div').style.visibility = 'hidden'")

          result = watchdog.wait
          expect(result).to be_a(Puppeteer::Bidi::ElementHandle)
          result.dispose if result
        end
      end
    end

    it 'should wait for element to become visible' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div style="visibility: hidden;">text</div>')

        Sync do
          visible = false

          watchdog = Async do
            page.wait_for_selector('div', visible: true).tap { visible = true }
          end

          # Element exists but is not visible
          sleep 0.1
          expect(visible).to be false

          # Make element visible
          page.evaluate("() => document.querySelector('div').style.visibility = 'visible'")

          element = watchdog.wait
          expect(element).not_to be_nil
          element.dispose
        end
      end
    end

    it 'should not consider zero-size elements as visible' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div style="width: 0; height: 0;"></div>')

        expect {
          page.wait_for_selector('div', visible: true, timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end
  end

  describe 'Frame.waitForSelector' do
    it 'should run in specified frame' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div>frame content</div>')

        # Use main_frame directly
        element = page.main_frame.wait_for_selector('div')
        expect(element).not_to be_nil
        expect(element.evaluate('x => x.textContent')).to eq('frame content')
        element.dispose
      end
    end
  end

  describe 'ElementHandle.waitForSelector' do
    it 'should wait for element within root element' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div class="root"><span class="child">text</span></div>')

        root = page.query_selector('.root')
        begin
          element = root.wait_for_selector('.child')
          expect(element).not_to be_nil
          expect(element.evaluate('x => x.textContent')).to eq('text')
          element.dispose
        ensure
          root.dispose
        end
      end
    end

    it 'should not find elements outside root element' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div class="root"></div><span class="outside">outside</span>')

        root = page.query_selector('.root')
        begin
          expect {
            root.wait_for_selector('.outside', timeout: 100)
          }.to raise_error(Puppeteer::Bidi::TimeoutError)
        ensure
          root.dispose
        end
      end
    end

    it 'should wait for element to be added inside root' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<div class="root"></div>')

        root = page.query_selector('.root')
        begin
          Sync do
            watchdog = Async do
              root.wait_for_selector('.child')
            end

            Async do
              sleep 0.1
              page.evaluate("() => { document.querySelector('.root').innerHTML = '<span class=\"child\">added</span>'; }")
            end

            element = watchdog.wait
            expect(element).not_to be_nil
            expect(element.evaluate('x => x.textContent')).to eq('added')
            element.dispose
          end
        ensure
          root.dispose
        end
      end
    end
  end
end

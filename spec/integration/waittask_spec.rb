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

  it 'should work with strict CSP policy' do
    with_test_state do |page:, server:, **|
      server.set_route('/csp.html') do |_req, res|
        res.status = 200
        res.add_header('Content-Security-Policy', "script-src #{server.prefix}")
        res.write('<html></html>')
        res.finish
      end

      page.goto("#{server.prefix}/csp.html")

      Sync do
        watchdog = Async do
          page.wait_for_function("() => window.__FOO === 'hit'", polling: 'raf')
        end
        page.evaluate("() => window.__FOO = 'hit'")

        watchdog.wait
      end
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

      page.set_default_timeout(1)

      expect {
        page.wait_for_function("() => false")
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /1ms exceeded/)
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

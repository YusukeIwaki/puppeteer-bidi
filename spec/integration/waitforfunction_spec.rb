# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Frame.waitForFunction', type: :integration do
  it 'should accept a string' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      watchdog = Thread.new do
        page.wait_for_function("() => window.__FOO === 1")
      end

      sleep 0.1
      page.evaluate("() => window.__FOO = 1")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should work when resolved right before execution context disposal' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      result = page.wait_for_function(<<~JS)
        () => {
          if (!window.__RELOADED) {
            window.__RELOADED = true;
            window.location.reload();
            return false;
          }
          return true;
        }
      JS

      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should poll on interval' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      start_time = Time.now

      watchdog = Thread.new do
        page.wait_for_function("() => window.__FOO === 'hit'", polling: 100)
      end

      sleep 0.05
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      elapsed = ((Time.now - start_time) * 1000).to_i

      # Should wait at least one polling interval
      expect(elapsed).to be >= 100

      result.dispose
    end
  end

  # TODO: Requires JavaScript-side MutationObserver polling
  # Currently Ruby-side polling triggers on any check, not just DOM mutations
  xit 'should poll on mutation' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      success = false

      watchdog = Thread.new do
        page.wait_for_function(
          "() => window.__FOO === 'hit'",
          polling: 'mutation'
        ).tap { success = true }
      end

      sleep 0.1

      # Set property without DOM mutation - should not resolve
      page.evaluate("() => window.__FOO = 'hit'")
      sleep 0.1
      expect(success).to be false

      # Trigger DOM mutation
      page.evaluate("() => document.body.appendChild(document.createElement('div'))")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  # TODO: Requires JavaScript-side MutationObserver polling
  # Currently Ruby-side polling triggers on any check, not just DOM mutations
  xit 'should poll on mutation async' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      success = false

      watchdog = Thread.new do
        page.wait_for_function(
          "async () => window.__FOO === 'hit'",
          polling: 'mutation'
        ).tap { success = true }
      end

      sleep 0.1

      # Set property without DOM mutation
      page.evaluate("() => window.__FOO = 'hit'")
      sleep 0.1
      expect(success).to be false

      # Trigger DOM mutation
      page.evaluate("() => document.body.appendChild(document.createElement('div'))")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should poll on raf' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      watchdog = Thread.new do
        page.wait_for_function("() => window.__FOO === 'hit'", polling: 'raf')
      end

      sleep 0.05
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should poll on raf async' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      watchdog = Thread.new do
        page.wait_for_function("async () => window.__FOO === 'hit'", polling: 'raf')
      end

      sleep 0.05
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should work with strict CSP policy' do
    with_test_state do |page:, server:, **|
      server.set_route('/empty.html') do |req, res|
        res.status = 200
        res['Content-Security-Policy'] = "script-src 'unsafe-eval'"
        res.body = '<html></html>'
      end

      page.goto("#{server.prefix}/empty.html")

      watchdog = Thread.new do
        page.wait_for_function("() => window.__FOO === 'hit'", polling: 'raf')
      end

      sleep 0.05
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
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
      result = page.wait_for_function("element => element.localName === 'div'", {}, div)

      expect(result).not_to be_nil
      result.dispose
      div.dispose
    end
  end

  # TODO: Timeout::ExitException escapes rescue clauses in Ruby-based polling
  # Needs investigation or refactor to JavaScript-side polling
  xit 'should respect timeout' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      expect {
        page.wait_for_function("() => false", timeout: 10)
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /10ms exceeded/)
    end
  end

  # TODO: Timeout::ExitException escapes rescue clauses in Ruby-based polling
  # Needs investigation or refactor to JavaScript-side polling
  xit 'should respect default timeout' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      # Set very short timeout
      expect {
        page.wait_for_function("() => false", timeout: 1)
      }.to raise_error(Puppeteer::Bidi::TimeoutError, /1ms exceeded/)
    end
  end

  it 'should disable timeout when set to 0' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      watchdog = Thread.new do
        page.wait_for_function(
          "() => window.__FOO === 'hit'",
          timeout: 0
        )
      end

      sleep 0.1
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should survive cross-process navigation' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      watchdog = Thread.new do
        page.wait_for_function("() => window.__FOO === 'hit'")
      end

      sleep 0.1
      page.goto("#{server.prefix}/grid.html")
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  it 'should survive navigations' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      watchdog = Thread.new do
        page.wait_for_function("() => window.__FOO === 'hit'")
      end

      sleep 0.1
      page.goto(server.empty_page)
      page.evaluate("() => window.__FOO = 'hit'")

      result = watchdog.value
      expect(result).not_to be_nil
      result.dispose
    end
  end

  # TODO: AbortController/signal support not implemented yet
  xit 'should be cancellable with an abort signal' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      # Requires AbortController implementation
    end
  end

  # TODO: AbortController/signal support not implemented yet
  xit 'should not cause a unhandled promise rejection when aborted' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      # Requires AbortController implementation
    end
  end
end

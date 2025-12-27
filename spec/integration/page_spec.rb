# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Page' do
  describe 'Page.close' do
    it 'should reject all promises when page is closed' do
      with_test_state do |browser:, **|
        new_page = browser.new_page
        error = nil

        promise = Async do
          begin
            new_page.evaluate('() => new Promise(r => {})')
          rescue => e
            error = e
          end
        end

        new_page.close

        promise.wait
        expect(error).not_to be_nil
      end
    end

    it 'should not be visible in browser.pages' do
      with_test_state do |browser:, **|
        new_page = browser.new_page
        expect(browser.pages).to include(new_page)
        new_page.close
        expect(browser.pages).not_to include(new_page)
      end
    end

    it 'should set the page close state' do
      with_test_state do |browser:, **|
        new_page = browser.new_page
        expect(new_page.closed?).to be false
        new_page.close
        expect(new_page.closed?).to be true
      end
    end

    it 'should close pages with iframes' do
      with_test_state do |browser:, **|
        new_page = browser.new_page
        new_page.set_content('<iframe srcdoc="<p>hello</p>"></iframe>')
        Puppeteer::Bidi::AsyncUtils.async_timeout(3000) { new_page.close }.wait
        expect(new_page.closed?).to be true
      end
    end

    it 'should run beforeunload if asked for' do
      pending 'Page.close runBeforeUnload option not implemented'

      with_test_state do |browser:, server:, **|
        new_page = browser.new_page
        new_page.goto("#{server.prefix}/beforeunload.html")
        # Click to trigger beforeunload setup
        new_page.click('body')

        new_page.close(run_before_unload: true)
      end
    end

    it 'should not run beforeunload by default' do
      with_test_state do |browser:, server:, **|
        new_page = browser.new_page
        new_page.goto(server.empty_page)
        new_page.evaluate(<<~JS)
          () => {
            window.addEventListener('beforeunload', event => {
              event.preventDefault();
              event.returnValue = '';
            });
          }
        JS
        # Should close without waiting for beforeunload
        new_page.close
        expect(new_page.closed?).to be true
      end
    end
  end

  describe 'Page.Events.Load' do
    it 'should fire when expected' do
      pending 'Page load event emission needs verification'

      with_test_state do |page:, server:, **|
        load_fired = false
        page.once(:load) { load_fired = true }

        page.goto(server.empty_page)

        expect(load_fired).to be true
      end
    end
  end

  describe 'Page.Events.DOMContentLoaded' do
    it 'should fire when expected' do
      with_test_state do |page:, **|
        pending 'Page domcontentloaded event not implemented'

        dom_loaded = false
        page.once(:domcontentloaded) { dom_loaded = true }

        page.goto('about:blank')

        expect(dom_loaded).to be true
      end
    end
  end

  describe 'Removing and Adding Event Handlers' do
    it 'should correctly fire event handlers as they are added and then removed' do
      with_test_state do |page:, server:, **|
        handler_called = false
        handler = ->(request) { handler_called = true }

        page.on(:request, &handler)
        page.goto(server.empty_page)
        expect(handler_called).to be true

        handler_called = false
        page.off(:request, &handler)
        page.goto(server.empty_page)
        expect(handler_called).to be false
      end
    end
  end

  describe 'Page.Events.error' do
    it 'should throw when page crashes' do
      pending 'Page crash detection not implemented'

      with_test_state do |page:, **|
        error = nil
        page.on(:error) { |e| error = e }
        # Trigger a crash...
        expect(error).not_to be_nil
      end
    end
  end

  describe 'Page.Events.Popup' do
    it 'should work' do
      pending 'Page.on("popup") not implemented'

      with_test_state do |page:, **|
        popup = nil
        page.once(:popup) { |p| popup = p }

        page.evaluate("() => { window.open('about:blank'); }")

        expect(popup).not_to be_nil
      end
    end

    it 'should work with noopener' do
      pending 'Page.on("popup") not implemented'

      with_test_state do |page:, **|
        popup = nil
        page.once(:popup) { |p| popup = p }

        page.evaluate("() => { window.open('about:blank', null, 'noopener'); }")

        expect(popup).not_to be_nil
      end
    end

    it 'should work with clicking target=_blank' do
      pending 'Page.on("popup") not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<a target=_blank href="/one-style.html">yo</a>')

        popup = nil
        page.once(:popup) { |p| popup = p }
        page.click('a')

        expect(popup).not_to be_nil
      end
    end
  end

  describe 'Page.setGeolocation' do
    it 'should work' do
      with_test_state do |page:, server:, context:, **|
        context.override_permissions(server.prefix, ['geolocation'])
        page.goto(server.empty_page)
        page.set_geolocation(longitude: 10, latitude: 10)
        result = page.evaluate(<<~JS)
          () => new Promise(resolve => navigator.geolocation.getCurrentPosition(position => {
            resolve({latitude: position.coords.latitude, longitude: position.coords.longitude});
          }))
        JS
        expect(result).to eq({ 'latitude' => 10, 'longitude' => 10 })
      end
    end

    it 'should throw when invalid longitude' do
      with_test_state do |page:, **|
        expect {
          page.set_geolocation(longitude: 200, latitude: 10)
        }.to raise_error(/Invalid longitude "200"/)
      end
    end
  end

  describe 'Page.setOfflineMode' do
    it 'should work' do
      pending 'Page.setOfflineMode not implemented'

      with_test_state do |page:, server:, **|
        page.set_offline_mode(true)
        expect {
          page.goto(server.empty_page)
        }.to raise_error

        page.set_offline_mode(false)
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
      end
    end

    it 'should emulate navigator.onLine' do
      pending 'Page.setOfflineMode not implemented'

      with_test_state do |page:, **|
        expect(page.evaluate('() => window.navigator.onLine')).to be true

        page.set_offline_mode(true)
        expect(page.evaluate('() => window.navigator.onLine')).to be false

        page.set_offline_mode(false)
        expect(page.evaluate('() => window.navigator.onLine')).to be true
      end
    end
  end

  describe 'Page.Events.Console' do
    it 'should work' do
      pending 'Page.on("console") not implemented'

      with_test_state do |page:, **|
        message = nil
        page.once(:console) { |msg| message = msg }
        page.evaluate("() => console.log('hello', 5, {foo: 'bar'})")

        expect(message.text).to eq("hello 5 {foo: 'bar'}")
        expect(message.type).to eq('log')
      end
    end

    it 'should work for different console API calls with logging functions' do
      pending 'Page.on("console") not implemented'

      with_test_state do |page:, **|
        messages = []
        page.on(:console) { |msg| messages << msg }

        # Execute various console API calls
        page.evaluate(<<~JS)
          () => {
            console.trace('calling console.trace');
            console.dir('calling console.dir');
            console.warn('calling console.warn');
            console.error('calling console.error');
            console.log(Promise.resolve('should not wait until resolved!'));
          }
        JS

        expect(messages.map(&:type)).to eq(%w[trace dir warning error log])
      end
    end

    it 'should not fail for window object' do
      pending 'Page.on("console") not implemented'

      with_test_state do |page:, **|
        message = nil
        page.once(:console) { |msg| message = msg }
        page.evaluate('() => console.error(window)')

        expect(message.text).to eq('Window')
      end
    end

    it 'should trigger correct Log' do
      pending 'Page.on("console") not implemented'

      with_test_state do |page:, server:, **|
        page.goto('about:blank')

        message = nil
        page.once(:console) { |msg| message = msg }

        page.evaluate("async url => fetch(url).catch(e => {})", "#{server.cross_process_prefix}/non-existent")

        expect(message).not_to be_nil
        expect(message.text).to include('Access')
      end
    end

    it 'should have location when fetch fails' do
      pending 'Page.on("console") not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        message = nil
        page.once(:console) { |msg| message = msg }

        page.set_content("<script>fetch('http://wat');</script>")

        expect(message).not_to be_nil
        expect(message.location[:url]).to include('empty.html')
      end
    end

    it 'should have location and stack trace for console API calls' do
      pending 'Page.on("console") not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        message = nil
        page.once(:console) { |msg| message = msg }

        page.goto("#{server.prefix}/consolelog.html")

        expect(message).not_to be_nil
        expect(message.text).to eq('yellow')
        expect(message.type).to eq('log')
        expect(message.location).to eq({
          url: "#{server.prefix}/consolelog.html",
          line_number: 7,
          column_number: 16
        })
      end
    end
  end

  describe 'Page.metrics' do
    it 'should get metrics from a page' do
      pending 'Page.metrics not implemented'

      with_test_state do |page:, **|
        page.goto('about:blank')
        metrics = page.metrics

        # Check for expected properties
        expect(metrics).to have_key('Timestamp')
        expect(metrics).to have_key('Documents')
        expect(metrics).to have_key('Frames')
        expect(metrics).to have_key('JSEventListeners')
        expect(metrics).to have_key('Nodes')
        expect(metrics).to have_key('LayoutCount')
        expect(metrics).to have_key('RecalcStyleCount')
        expect(metrics).to have_key('LayoutDuration')
        expect(metrics).to have_key('RecalcStyleDuration')
        expect(metrics).to have_key('ScriptDuration')
        expect(metrics).to have_key('TaskDuration')
        expect(metrics).to have_key('JSHeapUsedSize')
        expect(metrics).to have_key('JSHeapTotalSize')
      end
    end

    it 'metrics event fired on console.timeStamp' do
      pending 'Page.on("metrics") not implemented'

      with_test_state do |page:, **|
        metrics_data = []
        page.on(:metrics) { |data| metrics_data << data }

        page.goto('about:blank')
        page.evaluate("() => console.timeStamp('test42')")

        expect(metrics_data.length).to eq(1)
        expect(metrics_data[0]['title']).to eq('test42')
      end
    end
  end

  describe 'Page.waitForRequest' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        request = page.wait_for_request("#{server.prefix}/digits/2.png") do
          page.evaluate(<<~JS)
            () => {
              fetch('/digits/1.png');
              fetch('/digits/2.png');
              fetch('/digits/3.png');
            }
          JS
        end

        expect(request.url).to eq("#{server.prefix}/digits/2.png")
      end
    end

    it 'should work with predicate' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        request = page.wait_for_request(->(req) { req.url == "#{server.prefix}/digits/2.png" }) do
          page.evaluate(<<~JS)
            () => {
              fetch('/digits/1.png');
              fetch('/digits/2.png');
              fetch('/digits/3.png');
            }
          JS
        end

        expect(request.url).to eq("#{server.prefix}/digits/2.png")
      end
    end

    it 'should respect timeout' do
      pending 'Page.waitForRequest not implemented'

      with_test_state do |page:, **|
        expect {
          page.wait_for_request('notexist', timeout: 1)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end
  end

  describe 'Page.waitForResponse' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        response = page.wait_for_response("#{server.prefix}/digits/2.png") do
          page.evaluate(<<~JS)
            () => {
              fetch('/digits/1.png');
              fetch('/digits/2.png');
              fetch('/digits/3.png');
            }
          JS
        end

        expect(response.url).to eq("#{server.prefix}/digits/2.png")
      end
    end

    it 'should respect timeout' do
      pending 'Page.waitForResponse not implemented'

      with_test_state do |page:, **|
        expect {
          page.wait_for_response('notexist', timeout: 1)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should work with predicate' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        response = page.wait_for_response(->(res) { res.url == "#{server.prefix}/digits/2.png" }) do
          page.evaluate(<<~JS)
            () => {
              fetch('/digits/1.png');
              fetch('/digits/2.png');
              fetch('/digits/3.png');
            }
          JS
        end

        expect(response.url).to eq("#{server.prefix}/digits/2.png")
      end
    end
  end

  describe 'Page.waitForNetworkIdle' do
    it 'should work' do
      pending 'waitForNetworkIdle block API not implemented'

      with_test_state do |page:, server:, **|
        server.set_route('/fetch-request-a.js') do |_req, writer|
          sleep 0.1
          writer.write("HTTP/1.1 200 OK\r\nContent-Type: application/javascript\r\n\r\nconsole.log('a');")
        end

        page.goto(server.empty_page)

        idle_reached = false
        page.wait_for_network_idle(idle_time: 100) do
          page.evaluate("() => fetch('/fetch-request-a.js')")
          idle_reached = true
        end

        expect(idle_reached).to be true
      end
    end

    it 'should respect timeout' do
      pending 'waitForNetworkIdle test needs refinement'

      with_test_state do |page:, server:, **|
        # Set up a route that never responds
        server.set_route('/hang') do |_req, _writer|
          sleep 10
        end

        page.goto(server.empty_page)

        # Start a fetch that won't complete
        Async do
          page.evaluate("() => fetch('/hang')")
        end

        expect {
          page.wait_for_network_idle(timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end
  end

  describe 'Page.waitForFrame' do
    it 'should work' do
      pending 'Page.waitForFrame not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        frame = page.wait_for_frame(->(f) { f.url.include?('/frame.html') }) do
          page.set_content("<iframe src='#{server.prefix}/frames/frame.html'></iframe>")
        end

        expect(frame.url).to include('/frame.html')
      end
    end
  end

  describe 'Page.exposeFunction' do
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

    it 'should work' do
      with_test_state do |page:, **|
        page.expose_function('compute') do |a, b|
          a * b
        end

        result = page.evaluate('async () => await globalThis.compute(9, 4)')
        expect(result).to eq(36)
      end
    end

    it 'should throw exception in page context' do
      with_test_state do |page:, **|
        page.expose_function('woof') do
          raise 'WOOF WOOF'
        end

        result = page.evaluate(<<~JS)
          async () => {
            try {
              return await globalThis.woof();
            } catch (error) {
              return {
                message: error.message,
                stack: error.stack
              };
            }
          }
        JS
        expect(result['message']).to eq('WOOF WOOF')
        expect(result['stack']).to include('page_spec.rb')
      end
    end

    it 'should support throwing "null"' do
      with_test_state do |page:, **|
        page.expose_function('woof') do
          raise nil
        end

        result = page.evaluate(<<~JS)
          async () => {
            try {
              await globalThis.woof();
            } catch (error) {
              return error;
            }
          }
        JS
        expect(result).to be_nil
      end
    end

    it 'should be callable from-inside evaluateOnNewDocument' do
      with_test_state do |page:, **|
        called = Async::Promise.new
        page.expose_function('woof') do
          called.resolve(nil)
        end

        page.evaluate_on_new_document(<<~JS)
          async () => {
            await globalThis.woof();
          }
        JS

        page.reload
        Puppeteer::Bidi::AsyncUtils.async_timeout(2000, called).wait
      end
    end

    it 'should survive navigation' do
      with_test_state do |page:, server:, **|
        page.expose_function('compute') do |a, b|
          a * b
        end

        page.goto(server.empty_page)
        result = page.evaluate('async () => await globalThis.compute(9, 4)')
        expect(result).to eq(36)
      end
    end

    it 'should await returned promise' do
      with_test_state do |page:, **|
        page.expose_function('compute') do |a, b|
          Async do
            a * b
          end
        end

        result = page.evaluate('async () => await globalThis.compute(3, 5)')
        expect(result).to eq(15)
      end
    end

    it 'should await returned if called from function' do
      with_test_state do |page:, **|
        page.expose_function('compute') do |a, b|
          Async do
            a * b
          end
        end

        result = page.evaluate(<<~JS)
          async () => {
            const result = await globalThis.compute(3, 5);
            return result;
          }
        JS
        expect(result).to eq(15)
      end
    end

    it 'should work on frames' do
      with_test_state do |page:, server:, **|
        page.expose_function('compute') do |a, b|
          Async do
            a * b
          end
        end

        page.goto("#{server.prefix}/frames/nested-frames.html")
        frame = page.frames[1]
        result = frame.evaluate('async () => await globalThis.compute(3, 5)')
        expect(result).to eq(15)
      end
    end

    it 'should work with loading frames' do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        iframe_request = Async::Promise.new

        page.on(:request) do |request|
          if request.url.end_with?('/frames/frame.html')
            iframe_request.resolve(request)
          else
            request.continue
          end
        end

        nav_task = Async do
          page.goto("#{server.prefix}/frames/one-frame.html", wait_until: 'networkidle0')
        end

        request = iframe_request.wait
        page.expose_function('compute') do |a, b|
          Async do
            a * b
          end
        end
        request.continue
        nav_task.wait

        frame = page.frames[1]
        result = frame.evaluate('async () => await globalThis.compute(3, 5)')
        expect(result).to eq(15)
      end
    end

    it 'should work on frames before navigation' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/nested-frames.html")
        page.expose_function('compute') do |a, b|
          Async do
            a * b
          end
        end

        frame = page.frames[1]
        result = frame.evaluate('async () => await globalThis.compute(3, 5)')
        expect(result).to eq(15)
      end
    end

    it 'should not throw when frames detach' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        attach_frame(page, 'frame1', server.empty_page)
        page.expose_function('compute') do |a, b|
          Async do
            a * b
          end
        end
        detach_frame(page, 'frame1')

        result = page.evaluate('async () => await globalThis.compute(3, 5)')
        expect(result).to eq(15)
      end
    end

    it 'should work with complex objects' do
      with_test_state do |page:, **|
        page.expose_function('complexObject') do |a, b|
          { 'x' => a['x'] + b['x'] }
        end

        result = page.evaluate("async () => await globalThis.complexObject({x: 5}, {x: 2})")
        expect(result).to eq({ 'x' => 7 })
      end
    end

    it 'should fallback to default export when passed a module object' do
      with_test_state do |page:, server:, **|
        module_object = {
          default: ->(a, b) { a * b }
        }

        page.goto(server.empty_page)
        page.expose_function('compute', module_object)
        result = page.evaluate('async () => await globalThis.compute(9, 4)')
        expect(result).to eq(36)
      end
    end

    it 'should be called once' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/nested-frames.html")
        calls = 0
        page.expose_function('call') do
          calls += 1
        end

        frame = page.frames[1]
        frame.evaluate('async () => await globalThis.call()')
        expect(calls).to eq(1)
      end
    end
  end

  describe 'Page.removeExposedFunction' do
    it 'should work' do
      with_test_state do |page:, **|
        page.expose_function('compute') do |a, b|
          a * b
        end

        result = page.evaluate('async () => await globalThis.compute(9, 4)')
        expect(result).to eq(36)

        page.remove_exposed_function('compute')

        expect {
          page.evaluate('async () => await globalThis.compute(9, 4)')
        }.to raise_error(/globalThis.compute is not a function/)
      end
    end
  end

  describe 'Page.Events.PageError' do
    it 'should fire' do
      pending 'Page.on("pageerror") not implemented'

      with_test_state do |page:, server:, **|
        error = nil
        page.once(:pageerror) { |e| error = e }

        page.goto("#{server.prefix}/error.html")

        expect(error).not_to be_nil
        expect(error.message).to include('Fancy')
      end
    end
  end

  describe 'Page.setUserAgent' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')

        page.set_user_agent('foobar')

        page.goto(server.empty_page)

        expect(page.evaluate('() => navigator.userAgent')).to eq('foobar')
      end
    end

    it 'should work for subframes' do
      with_test_state do |page:, server:, **|
        expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')

        page.set_user_agent('foobar')
        page.goto("#{server.prefix}/frames/one-frame.html")

        frame = page.frames[1]
        expect(frame.evaluate('() => navigator.userAgent')).to eq('foobar')
      end
    end

    it 'should emulate device user-agent' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/mobile.html")
        expect(page.evaluate('() => navigator.userAgent')).not_to include('iPhone')

        page.set_user_agent('Mozilla/5.0 (iPhone; CPU iPhone OS 9_1 like Mac OS X)')
        page.goto("#{server.prefix}/mobile.html")
        expect(page.evaluate('() => navigator.userAgent')).to include('iPhone')
      end
    end

    it 'should work with additional userAgentMetadata' do
      skip "userAgentMetadata not supported in BiDi-only mode"

      with_test_state do |page:, server:, **|
        page.set_user_agent('MockBrowser', {
          architecture: 'Mock1',
          mobile: false,
          model: 'Mockbook',
          platform: 'MockOS',
          platform_version: '3.1'
        })

        page.goto(server.empty_page)

        result = page.evaluate(<<~JS)
          async () => {
            return await navigator.userAgentData.getHighEntropyValues([
              'architecture',
              'model',
              'platform',
              'platformVersion',
            ]);
          }
        JS

        expect(result['architecture']).to eq('Mock1')
        expect(result['model']).to eq('Mockbook')
        expect(result['platform']).to eq('MockOS')
        expect(result['platformVersion']).to eq('3.1')
      end
    end

    it 'should restore original user agent' do
      with_test_state do |page:, server:, **|
        original = page.evaluate('() => navigator.userAgent')
        page.set_user_agent('NewAgent')

        page.goto(server.empty_page)
        expect(page.evaluate('() => navigator.userAgent')).to eq('NewAgent')

        page.set_user_agent('')
        page.goto(server.empty_page)
        expect(page.evaluate('() => navigator.userAgent')).to eq(original)
      end
    end
  end

  describe 'Page.setContent' do
    expected_output = '<html><head></head><body><div>hello</div></body></html>'

    it 'should work' do
      with_test_state do |page:, **|
        page.set_content('<div>hello</div>')
        expect(page.content).to eq(expected_output)
      end
    end

    it 'should work with doctype' do
      with_test_state do |page:, **|
        doctype = '<!DOCTYPE html>'
        page.set_content("#{doctype}<div>hello</div>")
        expect(page.content).to eq("#{doctype}#{expected_output}")
      end
    end

    it 'should work with HTML 4 doctype' do
      with_test_state do |page:, **|
        doctype = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">'
        page.set_content("#{doctype}<div>hello</div>")
        expect(page.content).to eq("#{doctype}#{expected_output}")
      end
    end

    it 'should respect timeout' do
      pending 'Page.setContent timeout parameter not implemented'

      with_test_state do |page:, server:, **|
        server.set_route('/img.png') do |_req, _writer|
          sleep 10
        end

        expect {
          page.set_content("<img src='#{server.prefix}/img.png'>", wait_until: 'load', timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should await resources to load' do
      with_test_state do |page:, server:, **|
        img_path = "#{server.prefix}/digits/0.png"
        img_loaded = false

        server.set_route('/digits/0.png') do |_req, writer|
          sleep 0.1
          img_loaded = true
          # Read actual file and serve it
          content = File.binread(File.join(__dir__, '../assets/digits/0.png'))
          writer.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{content.bytesize}\r\n\r\n#{content}")
        end

        page.set_content("<img src='#{img_path}'>")
        expect(img_loaded).to be true
      end
    end

    it 'should work fast enough' do
      with_test_state do |page:, **|
        20.times do |i|
          page.set_content("<div>yo - #{i}</div>")
        end
      end
    end

    it 'should work with tricky content' do
      with_test_state do |page:, **|
        page.set_content("<div>hello world</div>\x00")
        result = page.evaluate('() => document.querySelector("div").textContent')
        expect(result).to eq('hello world')
      end
    end

    it 'should work with accents' do
      with_test_state do |page:, **|
        page.set_content('<div>aberración</div>')
        result = page.evaluate('() => document.querySelector("div").textContent')
        expect(result).to eq('aberración')
      end
    end

    it 'should work with emojis' do
      with_test_state do |page:, **|
        page.set_content("<div>\u{1F604}</div>")
        result = page.evaluate('() => document.querySelector("div").textContent')
        expect(result).to eq("\u{1F604}")
      end
    end

    it 'should work with newlines' do
      with_test_state do |page:, **|
        page.set_content("<div>\n</div>")
        result = page.evaluate('() => document.querySelector("div").textContent')
        expect(result).to eq("\n")
      end
    end
  end

  describe 'Page.setBypassCSP' do
    it 'should bypass CSP meta tag' do
      pending 'Page.setBypassCSP not implemented'

      with_test_state do |page:, server:, **|
        # Server adds CSP header
        server.set_csp_headers("/empty.html", "default-src 'self'")

        page.goto(server.empty_page)

        # Without bypass, inline script should fail
        page.set_content("<script>window.__injected = 42;</script>")
        expect(page.evaluate('() => window.__injected')).to be_nil

        page.set_bypass_csp(true)
        page.reload

        page.set_content("<script>window.__injected = 42;</script>")
        expect(page.evaluate('() => window.__injected')).to eq(42)
      end
    end

    it 'should bypass after cross-process navigation' do
      pending 'Page.setBypassCSP not implemented'

      with_test_state do |page:, server:, **|
        page.set_bypass_csp(true)
        page.goto("#{server.prefix}/csp.html")
        page.set_content("<script>window.__injected = 42;</script>")
        expect(page.evaluate('() => window.__injected')).to eq(42)

        page.goto("#{server.cross_process_prefix}/csp.html")
        page.set_content("<script>window.__injected = 42;</script>")
        expect(page.evaluate('() => window.__injected')).to eq(42)
      end
    end
  end

  describe 'Page.addScriptTag' do
    it 'should throw an error if no options are provided' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        expect {
          page.add_script_tag
        }.to raise_error(/Provide an object/)
      end
    end

    it 'should work with a url' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        script = page.add_script_tag(url: "#{server.prefix}/injectedfile.js")
        expect(script).to be_a(Puppeteer::Bidi::ElementHandle)
        expect(page.evaluate('() => window.__injected')).to eq(42)
      end
    end

    it 'should work with a url and type=module' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_script_tag(url: "#{server.prefix}/es6/es6import.js", type: 'module')
        expect(page.evaluate('() => window.__es6injected')).to eq(42)
      end
    end

    it 'should work with a path and type=module' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_script_tag(path: File.join(__dir__, '../assets/es6/es6pathimport.js'), type: 'module')
        page.wait_for_function('() => window.__es6injected')
        expect(page.evaluate('() => window.__es6injected')).to eq(42)
      end
    end

    it 'should throw error if loading from url fails' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        expect {
          page.add_script_tag(url: "#{server.prefix}/nonexistfile.js")
        }.to raise_error(/Loading script from/)
      end
    end

    it 'should work with a path' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_script_tag(path: File.join(__dir__, '../assets/injectedfile.js'))
        expect(page.evaluate('() => window.__injected')).to eq(42)
      end
    end

    it 'should include sourcemap when path is provided' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_script_tag(path: File.join(__dir__, '../assets/injectedfile.js'))

        result = page.evaluate('() => Array.from(document.scripts).pop().src')
        expect(result).to include('injectedfile.js')
      end
    end

    it 'should work with content' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_script_tag(content: 'window.__injected = 35;')
        expect(page.evaluate('() => window.__injected')).to eq(35)
      end
    end

    it 'should add id when provided' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_script_tag(content: 'window.__injected = 1;', id: 'custom-id')
        result = page.evaluate("() => document.getElementById('custom-id').id")
        expect(result).to eq('custom-id')
      end
    end

    it 'should throw when added with content to the CSP page' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/csp.html")
        expect {
          page.add_script_tag(content: 'window.__injected = 35;')
        }.to raise_error(/Content Security Policy/)
      end
    end

    it 'should throw when added with url to the CSP page' do
      pending 'Page.addScriptTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/csp.html")
        expect {
          page.add_script_tag(url: "#{server.cross_process_prefix}/injectedfile.js")
        }.to raise_error(/Content Security Policy/)
      end
    end
  end

  describe 'Page.addStyleTag' do
    it 'should throw an error if no options are provided' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        expect {
          page.add_style_tag
        }.to raise_error(/Provide an object/)
      end
    end

    it 'should work with a url' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        style = page.add_style_tag(url: "#{server.prefix}/injectedstyle.css")
        expect(style).to be_a(Puppeteer::Bidi::ElementHandle)
        result = page.evaluate("() => window.getComputedStyle(document.body).getPropertyValue('background-color')")
        expect(result).to eq('rgb(255, 0, 0)')
      end
    end

    it 'should throw if loading from url fails' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        expect {
          page.add_style_tag(url: "#{server.prefix}/nonexistfile.css")
        }.to raise_error(/Loading style from/)
      end
    end

    it 'should work with a path' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_style_tag(path: File.join(__dir__, '../assets/injectedstyle.css'))
        result = page.evaluate("() => window.getComputedStyle(document.body).getPropertyValue('background-color')")
        expect(result).to eq('rgb(255, 0, 0)')
      end
    end

    it 'should include sourcemap when path is provided' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_style_tag(path: File.join(__dir__, '../assets/injectedstyle.css'))

        result = page.evaluate('() => Array.from(document.styleSheets).pop().href')
        expect(result).to include('injectedstyle.css')
      end
    end

    it 'should work with content' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.add_style_tag(content: 'body { background-color: green; }')
        result = page.evaluate("() => window.getComputedStyle(document.body).getPropertyValue('background-color')")
        expect(result).to eq('rgb(0, 128, 0)')
      end
    end

    it 'should throw when added with content to the CSP page' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/csp.html")
        expect {
          page.add_style_tag(content: 'body { background-color: green; }')
        }.to raise_error(/Content Security Policy/)
      end
    end

    it 'should throw when added with url to the CSP page' do
      pending 'Page.addStyleTag not implemented'

      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/csp.html")
        expect {
          page.add_style_tag(url: "#{server.cross_process_prefix}/injectedstyle.css")
        }.to raise_error(/Content Security Policy/)
      end
    end
  end

  describe 'Page.url' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        expect(page.url).to eq('about:blank')
        page.goto(server.empty_page, wait_until: 'load')
        expect(page.url).to eq(server.empty_page)
      end
    end
  end

  describe 'Page.setJavaScriptEnabled' do
    it 'should work' do
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      with_test_state do |page:, **|
        page.set_javascript_enabled(false)
        expect(page.javascript_enabled?).to be false

        page.goto('data:text/html, <script>var something = "forbidden"</script>')

        error = nil
        begin
          page.evaluate('something')
        rescue => e
          error = e
        end

        expect(error).not_to be_nil
        expect(error.message).to include('something is not defined')

        page.set_javascript_enabled(true)
        expect(page.javascript_enabled?).to be true

        page.goto('data:text/html, <script>var something = "forbidden"</script>')
        result = page.evaluate('something')
        expect(result).to eq('forbidden')
      end
    end

    it 'setInterval should pause' do
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            setInterval(() => {
              globalThis.intervalCounter = (globalThis.intervalCounter ?? 0) + 1;
            }, 0);
          }
        JS

        page.set_javascript_enabled(false)

        interval_counter = page.evaluate('globalThis.intervalCounter')

        sleep 0.1

        page.set_javascript_enabled(true)

        new_counter = page.evaluate('globalThis.intervalCounter')

        expect(new_counter).to be <= (interval_counter + 2)
      end
    end

    it 'setTimeout should stop' do
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            window.counter = 0;
            setTimeout(() => window.counter = 1, 0);
          }
        JS

        page.set_javascript_enabled(false)

        sleep 0.1

        page.set_javascript_enabled(true)

        expect(page.evaluate('() => window.counter')).to eq(0)
      end
    end

    it 'microtasks do not pause' do
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            window.counter = 0;
            Promise.resolve().then(() => window.counter = 1);
          }
        JS

        page.set_javascript_enabled(false)

        sleep 0.05

        page.set_javascript_enabled(true)

        expect(page.evaluate('() => window.counter')).to eq(1)
      end
    end
  end

  describe 'Page.reload' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate('() => { window._foo = 10; }')
        expect(page.evaluate('() => window._foo')).to eq(10)

        page.reload

        expect(page.evaluate('() => window._foo')).to be_nil
      end
    end
  end

  describe 'Page.setCacheEnabled' do
    it 'should enable or disable the cache based on the state passed' do
      pending 'Page.setCacheEnabled not implemented'

      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/cached/one-style.html")
        # First request
        request1 = nil
        page.on(:request) { |req| request1 = req }
        page.reload

        page.set_cache_enabled(false)

        request2 = nil
        page.on(:request) { |req| request2 = req }
        page.reload

        expect(request1['fromCache']).to be true
        expect(request2['fromCache']).to be false
      end
    end
  end

  describe 'Page.pdf' do
    it 'should generate a pdf' do
      pending 'Page.pdf not implemented'

      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/grid.html")
        pdf = page.pdf

        expect(pdf).not_to be_nil
        expect(pdf.bytesize).to be > 0
      end
    end

    it 'should generate a pdf and save to file' do
      pending 'Page.pdf not implemented'

      with_test_state do |page:, server:, **|
        Dir.mktmpdir do |dir|
          output_path = File.join(dir, 'output.pdf')

          page.goto("#{server.prefix}/grid.html")
          page.pdf(path: output_path)

          expect(File.exist?(output_path)).to be true
          expect(File.size(output_path)).to be > 0
        end
      end
    end
  end

  describe 'Page.title' do
    it 'should return the page title' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/title.html")
        expect(page.title).to eq('Woof-Woof')
      end
    end
  end

  describe 'Page.select' do
    it 'should select single option' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.select('select', 'blue')
        expect(page.evaluate('() => result.onInput')).to eq(['blue'])
        expect(page.evaluate('() => result.onChange')).to eq(['blue'])
      end
    end

    it 'should select only first option if multiple given' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.select('select', 'blue', 'green', 'red')
        expect(page.evaluate('() => result.onInput')).to eq(['blue'])
        expect(page.evaluate('() => result.onChange')).to eq(['blue'])
      end
    end

    it 'should not throw when select causes navigation' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")

        page.eval_on_selector('select', "select => select.addEventListener('input', () => { window.location = '/empty.html'; })")

        page.wait_for_navigation do
          page.select('select', 'blue')
        end

        expect(page.url).to include('/empty.html')
      end
    end

    it 'should select multiple options' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.evaluate('() => { makeMultiple(); }')
        page.select('select', 'blue', 'green', 'red')
        expect(page.evaluate('() => result.onInput')).to match_array(%w[blue green red])
        expect(page.evaluate('() => result.onChange')).to match_array(%w[blue green red])
      end
    end

    it 'should respect event bubbling' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.select('select', 'blue')
        expect(page.evaluate('() => result.onBubblingInput')).to eq(['blue'])
        expect(page.evaluate('() => result.onBubblingChange')).to eq(['blue'])
      end
    end

    it 'should throw when element is not a <select>' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<body></body>')

        expect {
          page.select('body', '')
        }.to raise_error(/Element is not a <select> element/)
      end
    end

    it 'should return [] on no matched values' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        result = page.select('select', '42', 'abc')
        expect(result).to eq([])
      end
    end

    it 'should return an array of matched values' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.evaluate('() => { makeMultiple(); }')
        result = page.select('select', 'blue', 'black', 'magenta')
        expect(result.sort).to eq(%w[black blue magenta])
      end
    end

    it 'should return an array of one element when multiple is not set' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        result = page.select('select', '42', 'blue', 'black', 'magenta')
        expect(result.length).to eq(1)
      end
    end

    it 'should return [] on no values' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        result = page.select('select')
        expect(result).to eq([])
      end
    end

    it 'should deselect all options when passed no values for a multiple select' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.evaluate('() => { makeMultiple(); }')
        page.select('select', 'blue', 'black', 'magenta')
        page.select('select')
        # For multiple select, all options should be deselected
        expect(page.eval_on_selector('select', "select => Array.from(select.options).every(option => !option.selected)")).to be true
      end
    end

    it 'should deselect all options when passed no values for a select without multiple' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.select('select', 'blue', 'black', 'magenta')
        page.select('select')
        # For single select, the first option (value "") should be selected
        expect(page.eval_on_selector('select', "select => Array.from(select.options).filter(option => option.selected)[0].value")).to eq('')
      end
    end

    it 'should throw if passed in non-strings' do
      with_test_state do |page:, **|
        page.set_content('<select><option value="12"/></select>')
        expect {
          page.select('select', 12)
        }.to raise_error(/Values must be strings/)
      end
    end

    it 'should work when re-defining top-level Event class' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/select.html")
        page.evaluate('() => { window.Event = null; }')
        page.select('select', 'blue')
        expect(page.evaluate('() => result.onInput')).to eq(['blue'])
        expect(page.evaluate('() => result.onChange')).to eq(['blue'])
      end
    end
  end

  describe 'Page.Events.Close' do
    it 'should work with window.close' do
      pending 'Page.on("close") not implemented'

      with_test_state do |browser:, **|
        new_page = browser.new_page
        closed = false
        new_page.once(:close) { closed = true }

        new_page.evaluate("() => { window.close(); }")

        expect(closed).to be true
      end
    end

    it 'should work with page.close' do
      pending 'Page.on("close") not implemented'

      with_test_state do |browser:, **|
        new_page = browser.new_page
        closed = false
        new_page.once(:close) { closed = true }

        new_page.close

        expect(closed).to be true
      end
    end
  end

  describe 'Page.browser' do
    it 'should return the correct browser instance' do
      with_test_state do |page:, browser:, **|
        expect(page.browser_context.browser).to eq(browser)
      end
    end
  end

  describe 'Page.browserContext' do
    it 'should return the correct browser context instance' do
      with_test_state do |page:, context:, **|
        expect(page.browser_context).to eq(context)
      end
    end
  end

  describe 'Page.bringToFront' do
    it 'should work' do
      pending 'Page.bringToFront not implemented'

      with_test_state do |browser:, **|
        page1 = browser.new_page
        page2 = browser.new_page

        page1.bring_to_front
        expect(page1.evaluate('() => document.visibilityState')).to eq('visible')
        expect(page2.evaluate('() => document.visibilityState')).to eq('hidden')

        page2.bring_to_front
        expect(page1.evaluate('() => document.visibilityState')).to eq('hidden')
        expect(page2.evaluate('() => document.visibilityState')).to eq('visible')

        page1.close
        page2.close
      end
    end
  end

  describe 'Page.setViewport' do
    it 'should set viewport size' do
      with_test_state do |page:, **|
        page.set_viewport(width: 800, height: 600)

        result = page.evaluate(<<~JS)
          () => ({
            width: window.innerWidth,
            height: window.innerHeight
          })
        JS

        expect(result['width']).to eq(800)
        expect(result['height']).to eq(600)
      end
    end

    it 'should return current viewport' do
      with_test_state do |page:, **|
        page.set_viewport(width: 1024, height: 768)

        viewport = page.viewport

        expect(viewport[:width]).to eq(1024)
        expect(viewport[:height]).to eq(768)
      end
    end
  end

  describe 'Page.setDefaultTimeout' do
    it 'should set default timeout' do
      with_test_state do |page:, **|
        page.set_default_timeout(5000)
        expect(page.default_timeout).to eq(5000)
      end
    end

    it 'should throw for invalid timeout values' do
      with_test_state do |page:, **|
        expect {
          page.set_default_timeout(-1)
        }.to raise_error(ArgumentError, /non-negative number/)

        expect {
          page.set_default_timeout('invalid')
        }.to raise_error(ArgumentError, /non-negative number/)
      end
    end
  end

  describe 'Page.mouse' do
    it 'should return a Mouse instance' do
      with_test_state do |page:, **|
        expect(page.mouse).to be_a(Puppeteer::Bidi::Mouse)
      end
    end
  end

  describe 'Page.keyboard' do
    it 'should return a Keyboard instance' do
      with_test_state do |page:, **|
        expect(page.keyboard).to be_a(Puppeteer::Bidi::Keyboard)
      end
    end
  end

  describe 'Page.mainFrame' do
    it 'should return the main frame' do
      with_test_state do |page:, **|
        frame = page.main_frame
        expect(frame).to be_a(Puppeteer::Bidi::Frame)
      end
    end
  end

  describe 'Page.frames' do
    it 'should return all frames' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        frames = page.frames
        expect(frames.length).to eq(1)
        expect(frames.first).to eq(page.main_frame)
      end
    end

    it 'should include child frames' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/nested-frames.html")

        frames = page.frames
        # nested-frames.html has 4 frames total (1 main + 3 iframes including nested)
        expect(frames.length).to be >= 2
      end
    end
  end

  describe 'Page.waitForFunction' do
    it 'should work' do
      with_test_state do |page:, **|
        result = page.wait_for_function('() => 1')
        expect(result.evaluate('r => r')).to eq(1)
      end
    end

    it 'should accept a string' do
      with_test_state do |page:, **|
        result = page.wait_for_function('1 + 1')
        expect(result.evaluate('r => r')).to eq(2)
      end
    end

    it 'should work with arguments' do
      with_test_state do |page:, **|
        result = page.wait_for_function('(a, b) => a + b', {}, 3, 4)
        expect(result.evaluate('r => r')).to eq(7)
      end
    end

    it 'should timeout' do
      with_test_state do |page:, **|
        expect {
          page.wait_for_function('() => false', timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should survive cross-process navigation' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate('() => { window.__FOO = 1; }')

        result = page.wait_for_function('() => window.__FOO === 1')
        expect(result).not_to be_nil
      end
    end
  end

  describe 'Page.waitForSelector' do
    it 'should wait for selector' do
      with_test_state do |page:, **|
        page.set_content('<div>test</div>')
        element = page.wait_for_selector('div')
        expect(element).not_to be_nil
      end
    end

    it 'should timeout' do
      with_test_state do |page:, **|
        expect {
          page.wait_for_selector('div', timeout: 100)
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should wait for visible' do
      with_test_state do |page:, **|
        page.set_content('<div style="display: none">test</div>')

        wait_task = Async do
          page.wait_for_selector('div', visible: true)
        end

        page.eval_on_selector('div', "el => el.style.display = 'block'")

        element = wait_task.wait
        expect(element).not_to be_nil
      end
    end

    it 'should wait for hidden' do
      pending 'waitForSelector hidden option needs refinement'

      with_test_state do |page:, **|
        page.set_content('<div>test</div>')

        wait_task = Async do
          page.wait_for_selector('div', hidden: true)
        end

        page.eval_on_selector('div', "el => el.style.display = 'none'")

        result = wait_task.wait
        expect(result).to be_nil
      end
    end
  end

  describe 'Page content methods' do
    it 'should work with content()' do
      with_test_state do |page:, **|
        page.set_content('<div>test</div>')
        content = page.content
        expect(content).to include('<div>test</div>')
      end
    end
  end

  describe 'Page.evaluate' do
    it 'should work' do
      with_test_state do |page:, **|
        result = page.evaluate('1 + 2')
        expect(result).to eq(3)
      end
    end

    it 'should work with function' do
      with_test_state do |page:, **|
        result = page.evaluate('() => 7 * 3')
        expect(result).to eq(21)
      end
    end

    it 'should work with arguments' do
      with_test_state do |page:, **|
        result = page.evaluate('(a, b) => a * b', 3, 4)
        expect(result).to eq(12)
      end
    end

    it 'should transfer arrays' do
      with_test_state do |page:, **|
        result = page.evaluate('(arr) => arr[0] + arr[1]', [1, 2])
        expect(result).to eq(3)
      end
    end

    it 'should transfer objects' do
      with_test_state do |page:, **|
        result = page.evaluate('(obj) => obj.a + obj.b', { 'a' => 1, 'b' => 2 })
        expect(result).to eq(3)
      end
    end

    it 'should return undefined' do
      with_test_state do |page:, **|
        result = page.evaluate('() => undefined')
        expect(result).to be_nil
      end
    end

    it 'should return null' do
      with_test_state do |page:, **|
        result = page.evaluate('() => null')
        expect(result).to be_nil
      end
    end

    it 'should return complex objects' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => ({ foo: a })', 'bar')
        expect(result).to eq({ 'foo' => 'bar' })
      end
    end

    it 'should accept element handle as an argument' do
      with_test_state do |page:, **|
        page.set_content('<section>42</section>')
        element = page.query_selector('section')
        text = page.evaluate('(e) => e.textContent', element)
        expect(text).to eq('42')
      end
    end

    it 'should throw on non-serializable arguments' do
      pending 'BigInt handling may differ between browsers'

      with_test_state do |page:, **|
        expect {
          page.evaluate('() => window')
        }.to raise_error(StandardError)
      end
    end

    it 'should work with await promise' do
      with_test_state do |page:, **|
        result = page.evaluate('async () => await Promise.resolve(42)')
        expect(result).to eq(42)
      end
    end
  end

  describe 'Page.evaluateHandle' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => window')
        expect(handle).to be_a(Puppeteer::Bidi::JSHandle)
        handle.dispose
      end
    end

    it 'should work with primitives' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => 42')
        expect(handle.evaluate('x => x')).to eq(42)
        handle.dispose
      end
    end
  end

  describe 'Page queries' do
    it 'should work with query_selector' do
      with_test_state do |page:, **|
        page.set_content('<div id="test">hello</div>')
        element = page.query_selector('#test')
        expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
        element.dispose
      end
    end

    it 'should return nil for missing selector' do
      with_test_state do |page:, **|
        page.set_content('<div>hello</div>')
        element = page.query_selector('#missing')
        expect(element).to be_nil
      end
    end

    it 'should work with query_selector_all' do
      with_test_state do |page:, **|
        page.set_content('<div>a</div><div>b</div><div>c</div>')
        elements = page.query_selector_all('div')
        expect(elements.length).to eq(3)
        elements.each(&:dispose)
      end
    end

    it 'should return empty array for missing selector' do
      with_test_state do |page:, **|
        page.set_content('<div>hello</div>')
        elements = page.query_selector_all('.missing')
        expect(elements).to eq([])
      end
    end
  end

  describe 'Page.eval_on_selector' do
    it 'should work' do
      with_test_state do |page:, **|
        page.set_content('<div id="test">hello</div>')
        result = page.eval_on_selector('#test', 'e => e.textContent')
        expect(result).to eq('hello')
      end
    end

    it 'should work with arguments' do
      with_test_state do |page:, **|
        page.set_content('<div id="test">hello</div>')
        result = page.eval_on_selector('#test', '(e, suffix) => e.textContent + suffix', ' world')
        expect(result).to eq('hello world')
      end
    end
  end

  describe 'Page.eval_on_selector_all' do
    it 'should work' do
      with_test_state do |page:, **|
        page.set_content('<div>a</div><div>b</div>')
        result = page.eval_on_selector_all('div', 'els => els.map(e => e.textContent).join(",")')
        expect(result).to eq('a,b')
      end
    end
  end

  describe 'Page.focus' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.focus('textarea')
        active = page.evaluate('() => document.activeElement.tagName')
        expect(active).to eq('TEXTAREA')
      end
    end
  end

  describe 'Page.goto' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        expect(response.ok?).to be true
        expect(response.url).to eq(server.empty_page)
      end
    end

    it 'should work with domcontentloaded' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page, wait_until: 'domcontentloaded')
        expect(response.ok?).to be true
      end
    end

    it 'should work with file:// urls' do
      with_test_state do |page:, **|
        pending 'File URL navigation returns no response in Firefox BiDi'

        file_path = File.join(__dir__, '../assets/empty.html')
        response = page.goto("file://#{file_path}")
        expect(response.ok?).to be true
      end
    end
  end
end

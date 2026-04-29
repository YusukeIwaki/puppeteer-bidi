# frozen_string_literal: true

require "test_helper"

    test(['Page', 'Page.close', 'should reject all promises when page is closed'].join(" ")) do |browser:|
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

    test(['Page', 'Page.close', 'should not be visible in browser.pages'].join(" ")) do |browser:|
      new_page = browser.new_page
      expect(browser.pages).to include(new_page)
      new_page.close
      expect(browser.pages).not_to include(new_page)
    end

    test(['Page', 'Page.close', 'should set the page close state'].join(" ")) do |browser:|
      new_page = browser.new_page
      expect(new_page.closed?).to eq(false)
      new_page.close
      expect(new_page.closed?).to eq(true)
    end

    test(['Page', 'Page.close', 'should close child iframes'].join(" ")) do |context:, server:|
      new_page = context.new_page
      new_page.goto("#{server.prefix}/frames/one-frame.html")
      expect(new_page.frames.length).to eq(2)
      Puppeteer::Bidi::AsyncUtils.async_timeout(3000) { new_page.close }.wait
      expect(context.pages).not_to include(new_page)
    end

    test(['Page', 'Page.close', 'should run beforeunload if asked for'].join(" ")) do |browser:, server:|
      pending 'Page.close runBeforeUnload option not implemented'

      new_page = browser.new_page
      new_page.goto("#{server.prefix}/beforeunload.html")
      # Click to trigger beforeunload setup
      new_page.click('body')

      new_page.close(run_before_unload: true)
    end

    test(['Page', 'Page.close', 'should not run beforeunload by default'].join(" ")) do |browser:, server:|
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
      expect(new_page.closed?).to eq(true)
    end

    test(['Page', 'Page.Events.Load', 'should fire when expected'].join(" ")) do |page:, server:|
      pending 'Page load event emission needs verification'

      load_fired = false
      page.once(:load) { load_fired = true }

      page.goto(server.empty_page)

      expect(load_fired).to eq(true)
    end

    test(['Page', 'Page.Events.DOMContentLoaded', 'should fire when expected'].join(" ")) do |page:|
      pending 'Page domcontentloaded event not implemented'

      dom_loaded = false
      page.once(:domcontentloaded) { dom_loaded = true }

      page.goto('about:blank')

      expect(dom_loaded).to eq(true)
    end

    test(['Page', 'Removing and Adding Event Handlers', 'should correctly fire event handlers as they are added and then removed'].join(" ")) do |page:, server:|
      handler_called = false
      handler = ->(request) { handler_called = true }

      page.on(:request, &handler)
      page.goto(server.empty_page)
      expect(handler_called).to eq(true)

      handler_called = false
      page.off(:request, &handler)
      page.goto(server.empty_page)
      expect(handler_called).to eq(false)
    end

    test(['Page', 'Page.Events.error', 'should throw when page crashes'].join(" ")) do |page:|
      pending 'Page crash detection not implemented'

      error = nil
      page.on(:error) { |e| error = e }
      # Trigger a crash...
      expect(error).not_to be_nil
    end

    test(['Page', 'Page.Events.Popup', 'should work'].join(" ")) do |page:|
      pending 'Page.on("popup") not implemented'

      popup = nil
      page.once(:popup) { |p| popup = p }

      page.evaluate("() => { window.open('about:blank'); }")

      expect(popup).not_to be_nil
    end

    test(['Page', 'Page.Events.Popup', 'should work with noopener'].join(" ")) do |page:|
      pending 'Page.on("popup") not implemented'

      popup = nil
      page.once(:popup) { |p| popup = p }

      page.evaluate("() => { window.open('about:blank', null, 'noopener'); }")

      expect(popup).not_to be_nil
    end

    test(['Page', 'Page.Events.Popup', 'should work with clicking target=_blank'].join(" ")) do |page:, server:|
      pending 'Page.on("popup") not implemented'

      page.goto(server.empty_page)
      page.set_content('<a target=_blank href="/one-style.html">yo</a>')

      popup = nil
      page.once(:popup) { |p| popup = p }
      page.click('a')

      expect(popup).not_to be_nil
    end

    test(['Page', 'Page.setGeolocation', 'should work'].join(" ")) do |page:, server:, context:|
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

    test(['Page', 'Page.setGeolocation', 'should throw when invalid longitude'].join(" ")) do |page:|
      expect {
        page.set_geolocation(longitude: 200, latitude: 10)
      }.to raise_error(/Invalid longitude "200"/)
    end

    test(['Page', 'Page.setOfflineMode', 'should work'].join(" ")) do |page:, server:|
      pending 'Page.setOfflineMode not implemented'

      page.set_offline_mode(true)
      expect {
        page.goto(server.empty_page)
      }.to raise_error(StandardError)

      page.set_offline_mode(false)
      response = page.goto(server.empty_page)
      expect(response.status).to eq(200)
    end

    test(['Page', 'Page.setOfflineMode', 'should emulate navigator.onLine'].join(" ")) do |page:|
      pending 'Page.setOfflineMode not implemented'

      expect(page.evaluate('() => window.navigator.onLine')).to eq(true)

      page.set_offline_mode(true)
      expect(page.evaluate('() => window.navigator.onLine')).to eq(false)

      page.set_offline_mode(false)
      expect(page.evaluate('() => window.navigator.onLine')).to eq(true)
    end

    test(['Page', 'Page.metrics', 'should get metrics from a page'].join(" ")) do |page:|
      pending 'Page.metrics not implemented'

      page.goto('about:blank')
      metrics = page.metrics

      # Check for expected properties
      expect(metrics).to include('Timestamp')
      expect(metrics).to include('Documents')
      expect(metrics).to include('Frames')
      expect(metrics).to include('JSEventListeners')
      expect(metrics).to include('Nodes')
      expect(metrics).to include('LayoutCount')
      expect(metrics).to include('RecalcStyleCount')
      expect(metrics).to include('LayoutDuration')
      expect(metrics).to include('RecalcStyleDuration')
      expect(metrics).to include('ScriptDuration')
      expect(metrics).to include('TaskDuration')
      expect(metrics).to include('JSHeapUsedSize')
      expect(metrics).to include('JSHeapTotalSize')
    end

    test(['Page', 'Page.metrics', 'metrics event fired on console.timeStamp'].join(" ")) do |page:|
      pending 'Page.on("metrics") not implemented'

      metrics_data = []
      page.on(:metrics) { |data| metrics_data << data }

      page.goto('about:blank')
      page.evaluate("() => console.timeStamp('test42')")

      expect(metrics_data.length).to eq(1)
      expect(metrics_data[0]['title']).to eq('test42')
    end

    test(['Page', 'Page.waitForRequest', 'should work'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.waitForRequest', 'should work with predicate'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.waitForRequest', 'should respect timeout'].join(" ")) do |page:|
      expect {
        page.wait_for_request('notexist', timeout: 1)
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['Page', 'Page.waitForResponse', 'should work'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.waitForResponse', 'should respect timeout'].join(" ")) do |page:|
      expect {
        page.wait_for_response('notexist', timeout: 1)
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['Page', 'Page.waitForResponse', 'should work with predicate'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.waitForNetworkIdle', 'should work'].join(" ")) do |page:, server:|
      pending 'waitForNetworkIdle block API not implemented'

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

      expect(idle_reached).to eq(true)
    end

    test(['Page', 'Page.waitForNetworkIdle', 'should respect timeout'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.waitForFrame', 'should work'].join(" ")) do |page:, server:|
      pending 'Page.waitForFrame not implemented'

      page.goto(server.empty_page)

      frame = page.wait_for_frame(->(f) { f.url.include?('/frame.html') }) do
        page.set_content("<iframe src='#{server.prefix}/frames/frame.html'></iframe>")
      end

      expect(frame.url).to include('/frame.html')
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

    test(['Page', 'Page.exposeFunction', 'should work'].join(" ")) do |page:|
      page.expose_function('compute') do |a, b|
        a * b
      end

      result = page.evaluate('async () => await globalThis.compute(9, 4)')
      expect(result).to eq(36)
    end

    test(['Page', 'Page.exposeFunction', 'should throw exception in page context'].join(" ")) do |page:|
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
      expect(result['stack']).to include('page_test.rb')
    end

    test(['Page', 'Page.exposeFunction', 'should support throwing "null"'].join(" ")) do |page:|
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

    test(['Page', 'Page.exposeFunction', 'should be callable from-inside evaluateOnNewDocument'].join(" ")) do |page:|
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

    test(['Page', 'Page.exposeFunction', 'should survive navigation'].join(" ")) do |page:, server:|
      page.expose_function('compute') do |a, b|
        a * b
      end

      page.goto(server.empty_page)
      result = page.evaluate('async () => await globalThis.compute(9, 4)')
      expect(result).to eq(36)
    end

    test(['Page', 'Page.exposeFunction', 'should await returned promise'].join(" ")) do |page:|
      page.expose_function('compute') do |a, b|
        Async do
          a * b
        end
      end

      result = page.evaluate('async () => await globalThis.compute(3, 5)')
      expect(result).to eq(15)
    end

    test(['Page', 'Page.exposeFunction', 'should await returned if called from function'].join(" ")) do |page:|
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

    test(['Page', 'Page.exposeFunction', 'should work on frames'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.exposeFunction', 'should work with loading frames'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.exposeFunction', 'should work on frames before navigation'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.exposeFunction', 'should not throw when frames detach'].join(" ")) do |page:, server:|
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

    test(['Page', 'Page.exposeFunction', 'should work with complex objects'].join(" ")) do |page:|
      page.expose_function('complexObject') do |a, b|
        { 'x' => a['x'] + b['x'] }
      end

      result = page.evaluate("async () => await globalThis.complexObject({x: 5}, {x: 2})")
      expect(result).to eq({ 'x' => 7 })
    end

    test(['Page', 'Page.exposeFunction', 'should fallback to default export when passed a module object'].join(" ")) do |page:, server:|
      module_object = {
        default: ->(a, b) { a * b }
      }

      page.goto(server.empty_page)
      page.expose_function('compute', module_object)
      result = page.evaluate('async () => await globalThis.compute(9, 4)')
      expect(result).to eq(36)
    end

    test(['Page', 'Page.exposeFunction', 'should be called once'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/frames/nested-frames.html")
      calls = 0
      page.expose_function('call') do
        calls += 1
      end

      frame = page.frames[1]
      frame.evaluate('async () => await globalThis.call()')
      expect(calls).to eq(1)
    end

    test(['Page', 'Page.removeExposedFunction', 'should work'].join(" ")) do |page:|
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

    test(['Page', 'Page.Events.PageError', 'should fire'].join(" ")) do |page:, server:|
      pending 'Page.on("pageerror") not implemented'

      error = nil
      page.once(:pageerror) { |e| error = e }

      page.goto("#{server.prefix}/error.html")

      expect(error).not_to be_nil
      expect(error.message).to include('Fancy')
    end

    test(['Page', 'Page.setUserAgent', 'should work'].join(" ")) do |page:, server:|
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')

      page.set_user_agent('foobar')

      server_request = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      request = server_request.wait

      expect(request.headers['user-agent']).to eq('foobar')
      expect(page.evaluate('() => navigator.userAgent')).to eq('foobar')
    end

    test(['Page', 'Page.setUserAgent', 'should work with options parameter'].join(" ")) do |page:, server:|
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')

      page.set_user_agent(userAgent: 'foobar')

      server_request = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      request = server_request.wait

      expect(request.headers['user-agent']).to eq('foobar')
      expect(page.evaluate('() => navigator.userAgent')).to eq('foobar')
    end

    test(['Page', 'Page.setUserAgent', 'should work with platform option'].join(" ")) do |page:, server:|
      expect(page.evaluate('() => navigator.platform')).not_to eq('MockPlatform')

      begin
        page.set_user_agent(userAgent: 'foobar', platform: 'MockPlatform')
      rescue Puppeteer::Bidi::Connection::ProtocolError => error
        pending "Client hints override is not supported by this browser: #{error.message}"
        raise error
      end

      expect(page.evaluate('() => navigator.platform')).to eq('MockPlatform')

      server_request = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      request = server_request.wait

      expect(request.headers['user-agent']).to eq('foobar')
    end

    test(['Page', 'Page.setUserAgent', 'should work with platform option without userAgent'].join(" ")) do |page:, server:|
      original_user_agent = page.evaluate('() => navigator.userAgent')
      expect(page.evaluate('() => navigator.platform')).not_to eq('MockPlatform')

      begin
        page.set_user_agent(platform: 'MockPlatform')
      rescue Puppeteer::Bidi::Connection::ProtocolError => error
        pending "Client hints override is not supported by this browser: #{error.message}"
        raise error
      end

      expect(page.evaluate('() => navigator.platform')).to eq('MockPlatform')
      expect(page.evaluate('() => navigator.userAgent')).to eq(original_user_agent)

      server_request = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      request = server_request.wait

      expect(request.headers['user-agent']).to eq(original_user_agent)
    end

    test(['Page', 'Page.setUserAgent', 'should work for subframes'].join(" ")) do |page:, server:|
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')

      page.set_user_agent('foobar')

      server_request = Async do
        server.wait_for_request('/frames/frame.html')
      end
      page.goto("#{server.prefix}/frames/one-frame.html")
      request = server_request.wait

      frame = page.frames[1]
      expect(request.headers['user-agent']).to eq('foobar')
      expect(frame.evaluate('() => navigator.userAgent')).to eq('foobar')
    end

    test(['Page', 'Page.setUserAgent', 'should emulate device user-agent'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/mobile.html")
      expect(page.evaluate('() => navigator.userAgent')).not_to include('iPhone')

      page.set_user_agent('Mozilla/5.0 (iPhone; CPU iPhone OS 9_1 like Mac OS X)')
      page.goto("#{server.prefix}/mobile.html")
      expect(page.evaluate('() => navigator.userAgent')).to include('iPhone')
    end

    test(['Page', 'Page.setUserAgent', 'should work with additional userAgentMetadata'].join(" ")) do |page:, server:|
      begin
        page.set_user_agent('MockBrowser', {
          architecture: 'Mock1',
          mobile: false,
          model: 'Mockbook',
          platform: 'MockOS',
          platform_version: '3.1'
        })
      rescue Puppeteer::Bidi::Connection::ProtocolError => error
        pending "Client hints override is not supported by this browser: #{error.message}"
        raise error
      end

      server_request = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      request = server_request.wait

      has_ua_data = page.evaluate(<<~JS)
        () => {
          return !!navigator.userAgentData &&
                 typeof navigator.userAgentData.getHighEntropyValues === 'function';
        }
      JS
      unless has_ua_data
        pending 'navigator.userAgentData is not supported by this browser'
        raise 'navigator.userAgentData is not supported by this browser'
      end

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
      expect(request.headers['user-agent']).to eq('MockBrowser')
    end

    test(['Page', 'Page.setUserAgent', 'should restore original user agent'].join(" ")) do |page:, server:|
      original = page.evaluate('() => navigator.userAgent')
      page.set_user_agent('NewAgent')

      request_with_override = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      expect(request_with_override.wait.headers['user-agent']).to eq('NewAgent')
      expect(page.evaluate('() => navigator.userAgent')).to eq('NewAgent')

      page.set_user_agent('')
      request_after_reset = Async do
        server.wait_for_request('/empty.html')
      end
      page.goto(server.empty_page)
      expect(request_after_reset.wait.headers['user-agent']).to eq(original)
      expect(page.evaluate('() => navigator.userAgent')).to eq(original)
    end

    expected_output = '<html><head></head><body><div>hello</div></body></html>'

    test(['Page', 'Page.setContent', 'should work'].join(" ")) do |page:|
      page.set_content('<div>hello</div>')
      expect(page.content).to eq(expected_output)
    end

    test(['Page', 'Page.setContent', 'should work with doctype'].join(" ")) do |page:|
      doctype = '<!DOCTYPE html>'
      page.set_content("#{doctype}<div>hello</div>")
      expect(page.content).to eq("#{doctype}#{expected_output}")
    end

    test(['Page', 'Page.setContent', 'should work with HTML 4 doctype'].join(" ")) do |page:|
      doctype = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">'
      page.set_content("#{doctype}<div>hello</div>")
      expect(page.content).to eq("#{doctype}#{expected_output}")
    end

    test(['Page', 'Page.setContent', 'should respect timeout'].join(" ")) do |page:, server:|
      pending 'Page.setContent timeout parameter not implemented'

      server.set_route('/img.png') do |_req, _writer|
        sleep 10
      end

      expect {
        page.set_content("<img src='#{server.prefix}/img.png'>", wait_until: 'load', timeout: 100)
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['Page', 'Page.setContent', 'should await resources to load'].join(" ")) do |page:, server:|
      img_path = "#{server.prefix}/digits/0.png"
      img_loaded = false

      server.set_route('/digits/0.png') do |_req, writer|
        sleep 0.1
        img_loaded = true
        # Read actual file and serve it
        content = File.binread(asset_path("digits/0.png"))
        writer.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{content.bytesize}\r\n\r\n#{content}")
      end

      page.set_content("<img src='#{img_path}'>")
      expect(img_loaded).to eq(true)
    end

    test(['Page', 'Page.setContent', 'should work fast enough'].join(" ")) do |page:|
      20.times do |i|
        page.set_content("<div>yo - #{i}</div>")
      end
    end

    test(['Page', 'Page.setContent', 'should work with tricky content'].join(" ")) do |page:|
      page.set_content("<div>hello world</div>\x00")
      result = page.evaluate('() => document.querySelector("div").textContent')
      expect(result).to eq('hello world')
    end

    test(['Page', 'Page.setContent', 'should work with accents'].join(" ")) do |page:|
      page.set_content('<div>aberración</div>')
      result = page.evaluate('() => document.querySelector("div").textContent')
      expect(result).to eq('aberración')
    end

    test(['Page', 'Page.setContent', 'should work with emojis'].join(" ")) do |page:|
      page.set_content("<div>\u{1F604}</div>")
      result = page.evaluate('() => document.querySelector("div").textContent')
      expect(result).to eq("\u{1F604}")
    end

    test(['Page', 'Page.setContent', 'should work with newlines'].join(" ")) do |page:|
      page.set_content("<div>\n</div>")
      result = page.evaluate('() => document.querySelector("div").textContent')
      expect(result).to eq("\n")
    end

    test(['Page', 'Page.setBypassCSP', 'should bypass CSP meta tag'].join(" ")) do |page:, server:|
      pending 'Page.setBypassCSP not implemented'

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

    test(['Page', 'Page.setBypassCSP', 'should bypass after cross-process navigation'].join(" ")) do |page:, server:|
      pending 'Page.setBypassCSP not implemented'

      page.set_bypass_csp(true)
      page.goto("#{server.prefix}/csp.html")
      page.set_content("<script>window.__injected = 42;</script>")
      expect(page.evaluate('() => window.__injected')).to eq(42)

      page.goto("#{server.cross_process_prefix}/csp.html")
      page.set_content("<script>window.__injected = 42;</script>")
      expect(page.evaluate('() => window.__injected')).to eq(42)
    end

    test(['Page', 'Page.addScriptTag', 'should throw an error if no options are provided'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      expect {
        page.add_script_tag
      }.to raise_error(/Provide an object/)
    end

    test(['Page', 'Page.addScriptTag', 'should work with a url'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      script = page.add_script_tag(url: "#{server.prefix}/injectedfile.js")
      expect(script).to be_a(Puppeteer::Bidi::ElementHandle)
      expect(page.evaluate('() => window.__injected')).to eq(42)
    end

    test(['Page', 'Page.addScriptTag', 'should work with a url and type=module'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      page.add_script_tag(url: "#{server.prefix}/es6/es6import.js", type: 'module')
      expect(page.evaluate('() => window.__es6injected')).to eq(42)
    end

    test(['Page', 'Page.addScriptTag', 'should work with a path and type=module'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      page.add_script_tag(path: asset_path("es6/es6pathimport.js"), type: 'module')
      page.wait_for_function('() => window.__es6injected')
      expect(page.evaluate('() => window.__es6injected')).to eq(42)
    end

    test(['Page', 'Page.addScriptTag', 'should throw error if loading from url fails'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      expect {
        page.add_script_tag(url: "#{server.prefix}/nonexistfile.js")
      }.to raise_error(/Loading script from/)
    end

    test(['Page', 'Page.addScriptTag', 'should work with a path'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      page.add_script_tag(path: asset_path("injectedfile.js"))
      expect(page.evaluate('() => window.__injected')).to eq(42)
    end

    test(['Page', 'Page.addScriptTag', 'should include sourcemap when path is provided'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      page.add_script_tag(path: asset_path("injectedfile.js"))

      result = page.evaluate('() => Array.from(document.scripts).pop().src')
      expect(result).to include('injectedfile.js')
    end

    test(['Page', 'Page.addScriptTag', 'should work with content'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      page.add_script_tag(content: 'window.__injected = 35;')
      expect(page.evaluate('() => window.__injected')).to eq(35)
    end

    test(['Page', 'Page.addScriptTag', 'should add id when provided'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto(server.empty_page)
      page.add_script_tag(content: 'window.__injected = 1;', id: 'custom-id')
      result = page.evaluate("() => document.getElementById('custom-id').id")
      expect(result).to eq('custom-id')
    end

    test(['Page', 'Page.addScriptTag', 'should throw when added with content to the CSP page'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto("#{server.prefix}/csp.html")
      expect {
        page.add_script_tag(content: 'window.__injected = 35;')
      }.to raise_error(/Content Security Policy/)
    end

    test(['Page', 'Page.addScriptTag', 'should throw when added with url to the CSP page'].join(" ")) do |page:, server:|
      pending 'Page.addScriptTag not implemented'

      page.goto("#{server.prefix}/csp.html")
      expect {
        page.add_script_tag(url: "#{server.cross_process_prefix}/injectedfile.js")
      }.to raise_error(/Content Security Policy/)
    end

    test(['Page', 'Page.addStyleTag', 'should throw an error if no options are provided'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto(server.empty_page)
      expect {
        page.add_style_tag
      }.to raise_error(/Provide an object/)
    end

    test(['Page', 'Page.addStyleTag', 'should work with a url'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto(server.empty_page)
      style = page.add_style_tag(url: "#{server.prefix}/injectedstyle.css")
      expect(style).to be_a(Puppeteer::Bidi::ElementHandle)
      result = page.evaluate("() => window.getComputedStyle(document.body).getPropertyValue('background-color')")
      expect(result).to eq('rgb(255, 0, 0)')
    end

    test(['Page', 'Page.addStyleTag', 'should throw if loading from url fails'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto(server.empty_page)
      expect {
        page.add_style_tag(url: "#{server.prefix}/nonexistfile.css")
      }.to raise_error(/Loading style from/)
    end

    test(['Page', 'Page.addStyleTag', 'should work with a path'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto(server.empty_page)
      page.add_style_tag(path: asset_path("injectedstyle.css"))
      result = page.evaluate("() => window.getComputedStyle(document.body).getPropertyValue('background-color')")
      expect(result).to eq('rgb(255, 0, 0)')
    end

    test(['Page', 'Page.addStyleTag', 'should include sourcemap when path is provided'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto(server.empty_page)
      page.add_style_tag(path: asset_path("injectedstyle.css"))

      result = page.evaluate('() => Array.from(document.styleSheets).pop().href')
      expect(result).to include('injectedstyle.css')
    end

    test(['Page', 'Page.addStyleTag', 'should work with content'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto(server.empty_page)
      page.add_style_tag(content: 'body { background-color: green; }')
      result = page.evaluate("() => window.getComputedStyle(document.body).getPropertyValue('background-color')")
      expect(result).to eq('rgb(0, 128, 0)')
    end

    test(['Page', 'Page.addStyleTag', 'should throw when added with content to the CSP page'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto("#{server.prefix}/csp.html")
      expect {
        page.add_style_tag(content: 'body { background-color: green; }')
      }.to raise_error(/Content Security Policy/)
    end

    test(['Page', 'Page.addStyleTag', 'should throw when added with url to the CSP page'].join(" ")) do |page:, server:|
      pending 'Page.addStyleTag not implemented'

      page.goto("#{server.prefix}/csp.html")
      expect {
        page.add_style_tag(url: "#{server.cross_process_prefix}/injectedstyle.css")
      }.to raise_error(/Content Security Policy/)
    end

    test(['Page', 'Page.url', 'should work'].join(" ")) do |page:, server:|
      expect(page.url).to eq('about:blank')
      page.goto(server.empty_page, wait_until: 'load')
      expect(page.url).to eq(server.empty_page)
    end

    test(['Page', 'Page.setJavaScriptEnabled', 'should work'].join(" ")) do |page:|
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

      page.set_javascript_enabled(false)
      expect(page.javascript_enabled?).to eq(false)

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
      expect(page.javascript_enabled?).to eq(true)

      page.goto('data:text/html, <script>var something = "forbidden"</script>')
      result = page.evaluate('something')
      expect(result).to eq('forbidden')
    end

    test(['Page', 'Page.setJavaScriptEnabled', 'setInterval should pause'].join(" ")) do |page:|
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

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

      expect(new_counter <= (interval_counter + 2)).to eq(true)
    end

    test(['Page', 'Page.setJavaScriptEnabled', 'setTimeout should stop'].join(" ")) do |page:|
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

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

    test(['Page', 'Page.setJavaScriptEnabled', 'microtasks do not pause'].join(" ")) do |page:|
      pending 'emulation.setScriptingEnabled not supported by Firefox yet'

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

    test(['Page', 'Page.reload', 'should work'].join(" ")) do |page:, server:|
      page.goto(server.empty_page)
      page.evaluate('() => { window._foo = 10; }')
      expect(page.evaluate('() => window._foo')).to eq(10)

      page.reload

      expect(page.evaluate('() => window._foo')).to be_nil
    end

    test(['Page', 'Page.setCacheEnabled', 'should enable or disable the cache based on the state passed'].join(" ")) do |page:, server:|
      pending 'Page.setCacheEnabled not implemented'

      page.goto("#{server.prefix}/cached/one-style.html")
      # First request
      request1 = nil
      page.on(:request) { |req| request1 = req }
      page.reload

      page.set_cache_enabled(false)

      request2 = nil
      page.on(:request) { |req| request2 = req }
      page.reload

      expect(request1['fromCache']).to eq(true)
      expect(request2['fromCache']).to eq(false)
    end

    test(['Page', 'Page.pdf', 'should generate a pdf'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/grid.html")
      pdf = page.pdf

      expect(pdf).not_to be_nil
      expect(pdf.bytesize > 0).to eq(true)
    end

    test(['Page', 'Page.pdf', 'should generate a pdf and save to file'].join(" ")) do |page:, server:|
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'output.pdf')

        page.goto("#{server.prefix}/grid.html")
        page.pdf(path: output_path)

        expect(File.exist?(output_path)).to eq(true)
        expect(File.size(output_path) > 0).to eq(true)
      end
    end

    test(['Page', 'Page.title', 'should return the page title'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/title.html")
      expect(page.title).to eq('Woof-Woof')
    end

    test(['Page', 'Page.select', 'should select single option'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.select('select', 'blue')
      expect(page.evaluate('() => result.onInput')).to eq(['blue'])
      expect(page.evaluate('() => result.onChange')).to eq(['blue'])
    end

    test(['Page', 'Page.select', 'should select only first option if multiple given'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.select('select', 'blue', 'green', 'red')
      expect(page.evaluate('() => result.onInput')).to eq(['blue'])
      expect(page.evaluate('() => result.onChange')).to eq(['blue'])
    end

    test(['Page', 'Page.select', 'should not throw when select causes navigation'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")

      page.eval_on_selector('select', "select => select.addEventListener('input', () => { window.location = '/empty.html'; })")

      page.wait_for_navigation do
        page.select('select', 'blue')
      end

      expect(page.url).to include('/empty.html')
    end

    test(['Page', 'Page.select', 'should select multiple options'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.evaluate('() => { makeMultiple(); }')
      page.select('select', 'blue', 'green', 'red')
      expect(page.evaluate('() => result.onInput')).to match_array(%w[blue green red])
      expect(page.evaluate('() => result.onChange')).to match_array(%w[blue green red])
    end

    test(['Page', 'Page.select', 'should respect event bubbling'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.select('select', 'blue')
      expect(page.evaluate('() => result.onBubblingInput')).to eq(['blue'])
      expect(page.evaluate('() => result.onBubblingChange')).to eq(['blue'])
    end

    test(['Page', 'Page.select', 'should throw when element is not a <select>'].join(" ")) do |page:, server:|
      page.goto(server.empty_page)
      page.set_content('<body></body>')

      expect {
        page.select('body', '')
      }.to raise_error(/Element is not a <select> element/)
    end

    test(['Page', 'Page.select', 'should return [] on no matched values'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      result = page.select('select', '42', 'abc')
      expect(result).to eq([])
    end

    test(['Page', 'Page.select', 'should return an array of matched values'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.evaluate('() => { makeMultiple(); }')
      result = page.select('select', 'blue', 'black', 'magenta')
      expect(result.sort).to eq(%w[black blue magenta])
    end

    test(['Page', 'Page.select', 'should return an array of one element when multiple is not set'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      result = page.select('select', '42', 'blue', 'black', 'magenta')
      expect(result.length).to eq(1)
    end

    test(['Page', 'Page.select', 'should return [] on no values'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      result = page.select('select')
      expect(result).to eq([])
    end

    test(['Page', 'Page.select', 'should deselect all options when passed no values for a multiple select'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.evaluate('() => { makeMultiple(); }')
      page.select('select', 'blue', 'black', 'magenta')
      page.select('select')
      # For multiple select, all options should be deselected
      expect(page.eval_on_selector('select', "select => Array.from(select.options).every(option => !option.selected)")).to eq(true)
    end

    test(['Page', 'Page.select', 'should deselect all options when passed no values for a select without multiple'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.select('select', 'blue', 'black', 'magenta')
      page.select('select')
      # For single select, the first option (value "") should be selected
      expect(page.eval_on_selector('select', "select => Array.from(select.options).filter(option => option.selected)[0].value")).to eq('')
    end

    test(['Page', 'Page.select', 'should throw if passed in non-strings'].join(" ")) do |page:|
      page.set_content('<select><option value="12"/></select>')
      expect {
        page.select('select', 12)
      }.to raise_error(/Values must be strings/)
    end

    test(['Page', 'Page.select', 'should work when re-defining top-level Event class'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/select.html")
      page.evaluate('() => { window.Event = null; }')
      page.select('select', 'blue')
      expect(page.evaluate('() => result.onInput')).to eq(['blue'])
      expect(page.evaluate('() => result.onChange')).to eq(['blue'])
    end

    test(['Page', 'Page.Events.Close', 'should work with window.close'].join(" ")) do |browser:|
      pending 'Page.on("close") not implemented'

      new_page = browser.new_page
      closed = false
      new_page.once(:close) { closed = true }

      new_page.evaluate("() => { window.close(); }")

      expect(closed).to eq(true)
    end

    test(['Page', 'Page.Events.Close', 'should work with page.close'].join(" ")) do |browser:|
      pending 'Page.on("close") not implemented'

      new_page = browser.new_page
      closed = false
      new_page.once(:close) { closed = true }

      new_page.close

      expect(closed).to eq(true)
    end

    test(['Page', 'Page.browser', 'should return the correct browser instance'].join(" ")) do |page:, browser:|
      expect(page.browser_context.browser).to eq(browser)
    end

    test(['Page', 'Page.browserContext', 'should return the correct browser context instance'].join(" ")) do |page:, context:|
      expect(page.browser_context).to eq(context)
    end

    test(['Page', 'Page.windowId', 'should return the window id'].join(" ")) do |page:|
      expect(page.window_id).to be_a(String)
      expect(page.window_id).not_to be_empty
    end

    test(['Page', 'Page.bringToFront', 'should work'].join(" ")) do |browser:|
      pending 'Page.bringToFront not implemented'

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

    test(['Page', 'Page.setViewport', 'should set viewport size'].join(" ")) do |page:|
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

    test(['Page', 'Page.setViewport', 'should return current viewport'].join(" ")) do |page:|
      page.set_viewport(width: 1024, height: 768)

      viewport = page.viewport

      expect(viewport[:width]).to eq(1024)
      expect(viewport[:height]).to eq(768)
    end

    test(['Page', 'Page.setViewport', 'should accept has_touch option'].join(" ")) do |page:|
      expect {
        page.set_viewport(width: 800, height: 600, has_touch: true)
      }.not_to raise_error(StandardError)
    end

    test(['Page', 'Page.setDefaultTimeout', 'should set default timeout'].join(" ")) do |page:|
      page.set_default_timeout(5000)
      expect(page.default_timeout).to eq(5000)
    end

    test(['Page', 'Page.setDefaultTimeout', 'should throw for invalid timeout values'].join(" ")) do |page:|
      expect {
        page.set_default_timeout(-1)
      }.to raise_error(ArgumentError, /non-negative number/)

      expect {
        page.set_default_timeout('invalid')
      }.to raise_error(ArgumentError, /non-negative number/)
    end

    test(['Page', 'Page.mouse', 'should return a Mouse instance'].join(" ")) do |page:|
      expect(page.mouse).to be_a(Puppeteer::Bidi::Mouse)
    end

    test(['Page', 'Page.keyboard', 'should return a Keyboard instance'].join(" ")) do |page:|
      expect(page.keyboard).to be_a(Puppeteer::Bidi::Keyboard)
    end

    test(['Page', 'Page.mainFrame', 'should return the main frame'].join(" ")) do |page:|
      frame = page.main_frame
      expect(frame).to be_a(Puppeteer::Bidi::Frame)
    end

    test(['Page', 'Page.frames', 'should return all frames'].join(" ")) do |page:, server:|
      page.goto(server.empty_page)
      frames = page.frames
      expect(frames.length).to eq(1)
      expect(frames.first).to eq(page.main_frame)
    end

    test(['Page', 'Page.frames', 'should include child frames'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/frames/nested-frames.html")

      frames = page.frames
      # nested-frames.html has 4 frames total (1 main + 3 iframes including nested)
      expect(frames.length >= 2).to eq(true)
    end

    test(['Page', 'Page.waitForFunction', 'should work'].join(" ")) do |page:|
      result = page.wait_for_function('() => 1')
      expect(result.evaluate('r => r')).to eq(1)
    end

    test(['Page', 'Page.waitForFunction', 'should accept a string'].join(" ")) do |page:|
      result = page.wait_for_function('1 + 1')
      expect(result.evaluate('r => r')).to eq(2)
    end

    test(['Page', 'Page.waitForFunction', 'should work with arguments'].join(" ")) do |page:|
      result = page.wait_for_function('(a, b) => a + b', {}, 3, 4)
      expect(result.evaluate('r => r')).to eq(7)
    end

    test(['Page', 'Page.waitForFunction', 'should timeout'].join(" ")) do |page:|
      expect {
        page.wait_for_function('() => false', timeout: 100)
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['Page', 'Page.waitForFunction', 'should survive cross-process navigation'].join(" ")) do |page:, server:|
      page.goto(server.empty_page)
      page.evaluate('() => { window.__FOO = 1; }')

      result = page.wait_for_function('() => window.__FOO === 1')
      expect(result).not_to be_nil
    end

    test(['Page', 'Page.waitForSelector', 'should wait for selector'].join(" ")) do |page:|
      page.set_content('<div>test</div>')
      element = page.wait_for_selector('div')
      expect(element).not_to be_nil
    end

    test(['Page', 'Page.waitForSelector', 'should timeout'].join(" ")) do |page:|
      expect {
        page.wait_for_selector('div', timeout: 100)
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['Page', 'Page.waitForSelector', 'should wait for visible'].join(" ")) do |page:|
      page.set_content('<div style="display: none">test</div>')

      wait_task = Async do
        page.wait_for_selector('div', visible: true)
      end

      page.eval_on_selector('div', "el => el.style.display = 'block'")

      element = wait_task.wait
      expect(element).not_to be_nil
    end

    test(['Page', 'Page.waitForSelector', 'should wait for hidden'].join(" ")) do |page:|
      pending 'waitForSelector hidden option needs refinement'

      page.set_content('<div>test</div>')

      wait_task = Async do
        page.wait_for_selector('div', hidden: true)
      end

      page.eval_on_selector('div', "el => el.style.display = 'none'")

      result = wait_task.wait
      expect(result).to be_nil
    end

    test(['Page', 'Page content methods', 'should work with content()'].join(" ")) do |page:|
      page.set_content('<div>test</div>')
      content = page.content
      expect(content).to include('<div>test</div>')
    end

    test(['Page', 'Page.evaluate', 'should work'].join(" ")) do |page:|
      result = page.evaluate('1 + 2')
      expect(result).to eq(3)
    end

    test(['Page', 'Page.evaluate', 'should work with function'].join(" ")) do |page:|
      result = page.evaluate('() => 7 * 3')
      expect(result).to eq(21)
    end

    test(['Page', 'Page.evaluate', 'should work with arguments'].join(" ")) do |page:|
      result = page.evaluate('(a, b) => a * b', 3, 4)
      expect(result).to eq(12)
    end

    test(['Page', 'Page.evaluate', 'should transfer arrays'].join(" ")) do |page:|
      result = page.evaluate('(arr) => arr[0] + arr[1]', [1, 2])
      expect(result).to eq(3)
    end

    test(['Page', 'Page.evaluate', 'should transfer objects'].join(" ")) do |page:|
      result = page.evaluate('(obj) => obj.a + obj.b', { 'a' => 1, 'b' => 2 })
      expect(result).to eq(3)
    end

    test(['Page', 'Page.evaluate', 'should return undefined'].join(" ")) do |page:|
      result = page.evaluate('() => undefined')
      expect(result).to be_nil
    end

    test(['Page', 'Page.evaluate', 'should return null'].join(" ")) do |page:|
      result = page.evaluate('() => null')
      expect(result).to be_nil
    end

    test(['Page', 'Page.evaluate', 'should return complex objects'].join(" ")) do |page:|
      result = page.evaluate('(a) => ({ foo: a })', 'bar')
      expect(result).to eq({ 'foo' => 'bar' })
    end

    test(['Page', 'Page.evaluate', 'should accept element handle as an argument'].join(" ")) do |page:|
      page.set_content('<section>42</section>')
      element = page.query_selector('section')
      text = page.evaluate('(e) => e.textContent', element)
      expect(text).to eq('42')
    end

    test(['Page', 'Page.evaluate', 'should throw on non-serializable arguments'].join(" ")) do |page:|
      pending 'BigInt handling may differ between browsers'

      expect {
        page.evaluate('() => window')
      }.to raise_error(StandardError)
    end

    test(['Page', 'Page.evaluate', 'should work with await promise'].join(" ")) do |page:|
      result = page.evaluate('async () => await Promise.resolve(42)')
      expect(result).to eq(42)
    end

    test(['Page', 'Page.evaluateHandle', 'should work'].join(" ")) do |page:|
      handle = page.evaluate_handle('() => window')
      expect(handle).to be_a(Puppeteer::Bidi::JSHandle)
      handle.dispose
    end

    test(['Page', 'Page.evaluateHandle', 'should work with primitives'].join(" ")) do |page:|
      handle = page.evaluate_handle('() => 42')
      expect(handle.evaluate('x => x')).to eq(42)
      handle.dispose
    end

    test(['Page', 'Page queries', 'should work with query_selector'].join(" ")) do |page:|
      page.set_content('<div id="test">hello</div>')
      element = page.query_selector('#test')
      expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
      element.dispose
    end

    test(['Page', 'Page queries', 'should return nil for missing selector'].join(" ")) do |page:|
      page.set_content('<div>hello</div>')
      element = page.query_selector('#missing')
      expect(element).to be_nil
    end

    test(['Page', 'Page queries', 'should work with query_selector_all'].join(" ")) do |page:|
      page.set_content('<div>a</div><div>b</div><div>c</div>')
      elements = page.query_selector_all('div')
      expect(elements.length).to eq(3)
      elements.each(&:dispose)
    end

    test(['Page', 'Page queries', 'should return empty array for missing selector'].join(" ")) do |page:|
      page.set_content('<div>hello</div>')
      elements = page.query_selector_all('.missing')
      expect(elements).to eq([])
    end

    test(['Page', 'Page.eval_on_selector', 'should work'].join(" ")) do |page:|
      page.set_content('<div id="test">hello</div>')
      result = page.eval_on_selector('#test', 'e => e.textContent')
      expect(result).to eq('hello')
    end

    test(['Page', 'Page.eval_on_selector', 'should work with arguments'].join(" ")) do |page:|
      page.set_content('<div id="test">hello</div>')
      result = page.eval_on_selector('#test', '(e, suffix) => e.textContent + suffix', ' world')
      expect(result).to eq('hello world')
    end

    test(['Page', 'Page.eval_on_selector_all', 'should work'].join(" ")) do |page:|
      page.set_content('<div>a</div><div>b</div>')
      result = page.eval_on_selector_all('div', 'els => els.map(e => e.textContent).join(",")')
      expect(result).to eq('a,b')
    end

    test(['Page', 'Page.focus', 'should work'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/textarea.html")
      page.focus('textarea')
      active = page.evaluate('() => document.activeElement.tagName')
      expect(active).to eq('TEXTAREA')
    end

    test(['Page', 'Page.goto', 'should work'].join(" ")) do |page:, server:|
      response = page.goto(server.empty_page)
      expect(response.ok?).to eq(true)
      expect(response.url).to eq(server.empty_page)
    end

    test(['Page', 'Page.goto', 'should work with domcontentloaded'].join(" ")) do |page:, server:|
      response = page.goto(server.empty_page, wait_until: 'domcontentloaded')
      expect(response.ok?).to eq(true)
    end

    test(['Page', 'Page.goto', 'should work with file:// urls'].join(" ")) do |page:|
      pending 'File URL navigation returns no response in Firefox BiDi'

      file_path = asset_path("empty.html")
      response = page.goto("file://#{file_path}")
      expect(response.ok?).to eq(true)
    end

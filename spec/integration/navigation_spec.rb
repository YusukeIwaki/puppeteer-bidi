require 'spec_helper'

RSpec.describe 'Page.waitForNavigation' do
  it 'should work' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      response = page.wait_for_navigation do
        page.evaluate('url => { return (window.location.href = url) }', "#{server.prefix}/grid.html")
      end

      expect(response).not_to be_nil
      expect(response.ok?).to be true
      expect(response.url).to include('grid.html')
    end
  end

  it 'should work with both domcontentloaded and load' do
    with_test_state do |page:, server:, **|
      Sync do
        response_promise = Async::Promise.new
        server.set_route('/one-style.css') do |_request, writer|
          response_promise.wait
        end

        load_fired = false

        domcontentloaded_task = Async do
          page.wait_for_navigation(wait_until: 'domcontentloaded')
        end

        load_task = Async do
          page.wait_for_navigation(wait_until: 'load').tap do
            load_fired = true
          end
        end

        navigation_task = Async do
          page.goto("#{server.prefix}/one-style.html")
        end

        server.wait_for_request('/one-style.css')
        domcontentloaded_task.wait
        expect(load_fired).to eq(false)
        response_promise.resolve("It works!")
        Puppeteer::Bidi::AsyncUtils.await_promise_all([navigation_task, load_task])
      end
    end
  end

  it 'should work with clicking on anchor links' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.set_content('<a href="#foobar">foobar</a>')

      response = page.wait_for_navigation do
        page.click('a')
      end

      expect(response).to be_nil
      expect(page.url).to eq("#{server.empty_page}#foobar")
    end
  end

  it 'should work with history.pushState()' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.set_content(<<~HTML)
        <a onclick="javascript:pushState()">SPA</a>
        <script>
          function pushState() {
            history.pushState({}, '', 'wow.html');
          }
        </script>
      HTML

      response = page.wait_for_navigation do
        page.click('a')
      end

      expect(response).to be_nil
      expect(page.url).to eq("#{server.prefix}/wow.html")
    end
  end

  it 'should work with history.replaceState()' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.set_content(<<~HTML)
        <a onclick="javascript:replaceState()">SPA</a>
        <script>
          function replaceState() {
            history.replaceState({}, '', '/replaced.html');
          }
        </script>
      HTML

      response = page.wait_for_navigation do
        page.click('a')
      end

      expect(response).to be_nil
      expect(page.url).to eq("#{server.prefix}/replaced.html")
    end
  end

  it 'should work with DOM history.back()/history.forward()' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.set_content(<<~HTML)
        <a id="back" onclick="javascript:goBack()">back</a>
        <a id="forward" onclick="javascript:goForward()">forward</a>
        <script>
          function goBack() {
            history.back();
          }
          function goForward() {
            history.forward();
          }
          history.pushState({}, '', '/first.html');
          history.pushState({}, '', '/second.html');
        </script>
      HTML

      expect(page.url).to eq("#{server.prefix}/second.html")

      back_response = page.wait_for_navigation do
        page.click('a#back')
      end

      expect(back_response).to be_nil
      expect(page.url).to eq("#{server.prefix}/first.html")

      forward_response = page.wait_for_navigation do
        page.click('a#forward')
      end

      expect(forward_response).to be_nil
      expect(page.url).to eq("#{server.prefix}/second.html")
    end
  end

  it 'should work when subframe issues window.stop()' do
    skip 'Requires frame attachment event handling and complex navigation scenarios'
  end

  it 'should be cancellable' do
    skip 'Requires JS-specific AbortController/signal support.'
  end
end

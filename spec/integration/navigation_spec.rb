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
end

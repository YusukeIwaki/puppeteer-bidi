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
      # Puppeteer: await page.setContent('<a href="#foobar">foobar</a>');
      # Using evaluate as workaround since setContent changes base URL to data:
      page.evaluate('() => { document.body.innerHTML = \'<a href="#foobar">foobar</a>\' }')

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
      # Puppeteer: await page.setContent(html`...`);
      # Using evaluate as workaround since setContent changes base URL to data:
      page.evaluate(<<~JS)
        () => {
          document.body.innerHTML = '<a onclick="javascript:pushState()">SPA</a>';
          window.pushState = function() {
            history.pushState({}, '', 'wow.html');
          };
        }
      JS

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
      # Puppeteer: await page.setContent(html`...`);
      # Using evaluate as workaround since setContent changes base URL to data:
      page.evaluate(<<~JS)
        () => {
          document.body.innerHTML = '<a onclick="javascript:replaceState()">SPA</a>';
          window.replaceState = function() {
            history.replaceState({}, '', '/replaced.html');
          };
        }
      JS

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
      # Puppeteer: await page.setContent(html`...`);
      # Using evaluate as workaround since setContent changes base URL to data:
      page.evaluate(<<~JS)
        () => {
          history.pushState({}, '', '/first.html');
          history.pushState({}, '', '/second.html');
          document.body.innerHTML = `
            <a id="back" onclick="javascript:goBack()">back</a>
            <a id="forward" onclick="javascript:goForward()">forward</a>
          `;
          window.goBack = function() { history.back(); };
          window.goForward = function() { history.forward(); };
        }
      JS

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

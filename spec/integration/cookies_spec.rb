# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Cookie specs' do
  def with_cookie_state
    with_test_state do |browser:, server:, **|
      context = browser.create_browser_context
      page = context.new_page

      begin
        yield(page: page, server: server, https_server: $shared_https_test_server,
              browser: browser, context: context)
      ensure
        page.close unless page.closed?
        context.close
      end
    end
  end

  def origin_for(url)
    uri = URI.parse(url)
    origin = "#{uri.scheme}://#{uri.host}"
    return origin if uri.port.nil?

    default_port = uri.scheme == "https" ? 443 : 80
    uri.port == default_port ? origin : "#{origin}:#{uri.port}"
  end

  describe 'Page.cookies' do
    it 'should return no cookies in pristine browser context' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        expect_cookie_equals(page.cookies, [], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should get a cookie' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        page.evaluate("document.cookie = 'username=John Doe'")

        expect_cookie_equals(page.cookies, [
          {
            name: 'username',
            value: 'John Doe',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 16,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should properly report httpOnly cookie' do
      with_cookie_state do |page:, server:, **|
        server.set_route('/empty.html') do |_request, writer|
          writer.add_header('set-cookie', 'a=b; HttpOnly; Path=/')
          writer.finish
        end
        page.goto(server.empty_page)
        cookies = page.cookies
        expect(cookies.length).to eq(1)
        expect(cookies[0]['httpOnly']).to be(true)
      end
    end

    it 'should properly report "Strict" sameSite cookie' do
      with_cookie_state do |page:, server:, **|
        server.set_route('/empty.html') do |_request, writer|
          writer.add_header('set-cookie', 'a=b; SameSite=Strict')
          writer.finish
        end
        page.goto(server.empty_page)
        cookies = page.cookies
        expect(cookies.length).to eq(1)
        expect(cookies[0]['sameSite']).to eq('Strict')
      end
    end

    it 'should properly report "Lax" sameSite cookie' do
      with_cookie_state do |page:, server:, **|
        server.set_route('/empty.html') do |_request, writer|
          writer.add_header('set-cookie', 'a=b; SameSite=Lax')
          writer.finish
        end
        page.goto(server.empty_page)
        cookies = page.cookies
        expect(cookies.length).to eq(1)
        expect(cookies[0]['sameSite']).to eq('Lax')
      end
    end

    it 'should get multiple cookies' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        page.evaluate(<<~JS)
          document.cookie = 'username=John Doe';
          document.cookie = 'password=1234';
        JS
        cookies = page.cookies.sort_by { |cookie| cookie['name'] }
        expect_cookie_equals(cookies, [
          {
            name: 'password',
            value: '1234',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 12,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
          {
            name: 'username',
            value: 'John Doe',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 16,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should get cookies from multiple urls' do
      with_cookie_state do |page:, browser:, **|
        page.set_cookie(
          {
            url: 'https://foo.com',
            name: 'doggo',
            value: 'woofs',
          },
          {
            url: 'https://bar.com',
            name: 'catto',
            value: 'purrs',
          },
          {
            url: 'https://baz.com',
            name: 'birdo',
            value: 'tweets',
          }
        )
        cookies = page.cookies('https://foo.com', 'https://baz.com')
        cookies = cookies.sort_by { |cookie| cookie['name'] }
        expect_cookie_equals(cookies, [
          {
            name: 'birdo',
            value: 'tweets',
            domain: 'baz.com',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 11,
            httpOnly: false,
            session: true,
            sourceScheme: 'Secure',
          },
          {
            name: 'doggo',
            value: 'woofs',
            domain: 'foo.com',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 10,
            httpOnly: false,
            session: true,
            sourceScheme: 'Secure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should get cookies from subdomain if the domain field allows it' do
      with_cookie_state do |page:, **|
        page.set_cookie(
          url: 'https://base_domain.com',
          domain: '.base_domain.com',
          name: 'doggo',
          value: 'woofs'
        )
        cookies = page.cookies('https://sub_domain.base_domain.com')
        expect(cookies.length).to eq(1)
      end
    end

    it 'should not get cookies from subdomain if the cookie is for top-level domain' do
      with_cookie_state do |page:, **|
        page.set_cookie(
          url: 'https://base_domain.com',
          domain: 'base_domain.com',
          name: 'doggo',
          value: 'woofs'
        )
        cookies = page.cookies('https://sub_domain.base_domain.com')
        expect(cookies.length).to eq(0)
      end
    end

    it 'should get cookies from nested path' do
      with_cookie_state do |page:, **|
        page.set_cookie(
          url: 'https://foo.com',
          path: '/some_path',
          name: 'doggo',
          value: 'woofs'
        )
        cookies = page.cookies('https://foo.com/some_path/nested_path')
        expect(cookies.length).to eq(1)
      end
    end

    it 'should not get cookies from not nested path' do
      with_cookie_state do |page:, **|
        page.set_cookie(
          url: 'https://foo.com',
          path: '/some_path',
          name: 'doggo',
          value: 'woofs'
        )
        cookies = page.cookies('https://foo.com/some_path_looks_like_nested')
        expect(cookies.length).to eq(0)
      end
    end
  end

  describe 'Page.set_cookie' do
    it 'should work' do
      with_cookie_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie(name: 'password', value: '123456')
        expect(page.evaluate('document.cookie')).to eq('password=123456')
      end
    end

    it 'should isolate cookies in browser contexts' do
      with_cookie_state do |page:, server:, browser:, **|
        another_context = browser.create_browser_context
        begin
          another_page = another_context.new_page

          page.goto(server.empty_page)
          another_page.goto(server.empty_page)

          page.set_cookie(name: 'page1cookie', value: 'page1value')
          another_page.set_cookie(name: 'page2cookie', value: 'page2value')

          cookies1 = page.cookies
          cookies2 = another_page.cookies
          expect(cookies1.length).to eq(1)
          expect(cookies2.length).to eq(1)
          expect(cookies1[0]['name']).to eq('page1cookie')
          expect(cookies1[0]['value']).to eq('page1value')
          expect(cookies2[0]['name']).to eq('page2cookie')
          expect(cookies2[0]['value']).to eq('page2value')
        ensure
          another_context.close
        end
      end
    end

    it 'should set multiple cookies' do
      with_cookie_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie(
          {
            name: 'password',
            value: '123456',
          },
          {
            name: 'foo',
            value: 'bar',
          }
        )
        cookie_strings = page.evaluate(<<~JS)
          () => {
            const cookies = document.cookie.split(';');
            return cookies.map(cookie => cookie.trim()).sort();
          }
        JS

        expect(cookie_strings).to eq(['foo=bar', 'password=123456'])
      end
    end

    it 'should have |expires| set to |-1| for session cookies' do
      with_cookie_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie(name: 'password', value: '123456')
        cookies = page.cookies
        expect(cookies[0]['session']).to be(true)
        expect(cookies[0]['expires']).to eq(-1)
      end
    end

    it 'should set cookie with reasonable defaults' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        page.set_cookie(name: 'password', value: '123456')
        cookies = page.cookies.sort_by { |cookie| cookie['name'] }
        expect_cookie_equals(cookies, [
          {
            name: 'password',
            value: '123456',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 14,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should set cookie with all available properties' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        page.set_cookie(
          name: 'password',
          value: '123456',
          domain: 'localhost',
          path: '/',
          sameParty: false,
          expires: -1,
          httpOnly: false,
          secure: false,
          sourceScheme: 'Unset'
        )
        cookies = page.cookies.sort_by { |cookie| cookie['name'] }
        expect_cookie_equals(cookies, [
          {
            name: 'password',
            value: '123456',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 14,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'Unset',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should set a cookie with a path' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto("#{server.prefix}/grid.html")
        page.set_cookie(
          name: 'gridcookie',
          value: 'GRID',
          path: '/grid.html'
        )
        expect_cookie_equals(page.cookies, [
          {
            name: 'gridcookie',
            value: 'GRID',
            domain: 'localhost',
            path: '/grid.html',
            sameParty: false,
            expires: -1,
            size: 14,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
        expect(page.evaluate('document.cookie')).to eq('gridcookie=GRID')
        page.goto(server.empty_page)
        expect_cookie_equals(page.cookies, [], chrome: browser.user_agent.include?("Chrome"))
        expect(page.evaluate('document.cookie')).to eq('')
        page.goto("#{server.prefix}/grid.html")
        expect(page.evaluate('document.cookie')).to eq('gridcookie=GRID')
      end
    end

    it 'should set a cookie with a partitionKey' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        origin = origin_for(page.url)
        page.set_cookie(
          url: page.url,
          name: 'partitionCookie',
          value: 'partition',
          secure: true,
          partitionKey: origin
        )
        expect_cookie_equals(page.cookies, [
          {
            name: 'partitionCookie',
            value: 'partition',
            domain: URI.parse(page.url).host,
            path: '/',
            expires: -1,
            size: 24,
            httpOnly: false,
            secure: true,
            session: true,
            sameParty: false,
            sourceScheme: 'Secure',
            partitionKey: origin,
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should not set a cookie on a blank page' do
      with_cookie_state do |page:, **|
        page.goto('about:blank')
        error = nil
        begin
          page.set_cookie(name: 'example-cookie', value: 'best')
        rescue => e
          error = e
        end
        expect(error.message).to include('At least one of the url and domain needs to be specified')
      end
    end

    it 'should not set a cookie with blank page URL' do
      with_cookie_state do |page:, server:, **|
        error = nil
        page.goto(server.empty_page)
        begin
          page.set_cookie(
            { name: 'example-cookie', value: 'best' },
            { url: 'about:blank', name: 'example-cookie-blank', value: 'best' }
          )
        rescue => e
          error = e
        end
        expect(error.message).to eq('Blank page can not have cookie "example-cookie-blank"')
      end
    end

    it 'should not set a cookie on a data URL page' do
      with_cookie_state do |page:, **|
        error = nil
        page.goto('data:,Hello%2C%20World!')
        begin
          page.set_cookie(name: 'example-cookie', value: 'best')
        rescue => e
          error = e
        end
        expect(error.message).to include('At least one of the url and domain needs to be specified')
      end
    end

    it 'should default to setting secure cookie for HTTPS websites' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        secure_url = 'https://example.com'
        page.set_cookie(url: secure_url, name: 'foo', value: 'bar')
        cookie = page.cookies(secure_url)[0]
        if browser.user_agent.include?("Chrome")
          expect(cookie['secure']).to be(true)
        else
          expect(cookie['secure']).to be(false)
        end
      end
    end

    it 'should be able to set insecure cookie for HTTP website' do
      with_cookie_state do |page:, server:, **|
        page.goto(server.empty_page)
        http_url = 'http://example.com'
        page.set_cookie(url: http_url, name: 'foo', value: 'bar')
        cookie = page.cookies(http_url)[0]
        expect(cookie['secure']).to be(false)
      end
    end

    it 'should set a cookie on a different domain' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto(server.empty_page)
        page.set_cookie(
          url: 'https://www.example.com',
          name: 'example-cookie',
          value: 'best'
        )
        expect(page.evaluate('document.cookie')).to eq('')
        expect_cookie_equals(page.cookies, [], chrome: browser.user_agent.include?("Chrome"))
        expect_cookie_equals(page.cookies('https://www.example.com'), [
          {
            name: 'example-cookie',
            value: 'best',
            domain: 'www.example.com',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 18,
            httpOnly: false,
            session: true,
            sourceScheme: 'Secure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should set cookies from a frame' do
      with_cookie_state do |page:, server:, browser:, **|
        page.goto("#{server.prefix}/grid.html")
        page.set_cookie(name: 'localhost-cookie', value: 'best')
        page.evaluate(<<~JS, server.cross_process_prefix)
          src => {
            let fulfill;
            const promise = new Promise(x => (fulfill = x));
            const iframe = document.createElement('iframe');
            document.body.appendChild(iframe);
            iframe.onload = fulfill;
            iframe.src = src;
            return promise;
          }
        JS
        page.set_cookie(
          name: '127-cookie',
          value: 'worst',
          url: server.cross_process_prefix
        )
        expect(page.evaluate('document.cookie')).to eq('localhost-cookie=best')

        expect_cookie_equals(page.cookies, [
          {
            name: 'localhost-cookie',
            value: 'best',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 20,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))

        expect_cookie_equals(page.cookies(server.cross_process_prefix), [
          {
            name: '127-cookie',
            value: 'worst',
            domain: '127.0.0.1',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 15,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should set secure same-site cookies from a frame' do
      with_cookie_state do |page:, https_server:, browser:, **|
        is_chrome = browser.user_agent.include?("Chrome")
        page.goto("#{https_server.prefix}/grid.html")
        page.evaluate(<<~JS, https_server.cross_process_prefix)
          src => {
            let fulfill;
            const promise = new Promise(x => (fulfill = x));
            const iframe = document.createElement('iframe');
            document.body.appendChild(iframe);
            iframe.onload = fulfill;
            iframe.src = src;
            return promise;
          }
        JS
        if is_chrome
          page.set_cookie(
            name: '127-same-site-cookie',
            value: 'best',
            url: https_server.cross_process_prefix,
            sameSite: 'None'
          )

          frame_cookie = page.frames[1].evaluate('document.cookie')
          expect(frame_cookie).to eq('127-same-site-cookie=best')
          expect_cookie_equals(page.cookies(https_server.cross_process_prefix), [
            {
              name: '127-same-site-cookie',
              value: 'best',
              domain: '127.0.0.1',
              path: '/',
              sameParty: false,
              expires: -1,
              size: 24,
              httpOnly: false,
              sameSite: 'None',
              secure: true,
              session: true,
              sourceScheme: 'Secure',
            },
          ], chrome: true)
        else
          error = nil
          begin
            page.set_cookie(
              name: '127-same-site-cookie',
              value: 'best',
              url: https_server.cross_process_prefix,
              sameSite: 'None'
            )
          rescue => e
            error = e
          end
          expect(error).not_to be_nil
          expect(error.message).to match(/samesite=.*none/i)
          expect(error.message).to match(/secure/i)
          expect(page.cookies(https_server.cross_process_prefix)).to eq([])
        end
      end
    end
  end

  describe 'Page.delete_cookie' do
    it 'should delete cookie' do
      with_cookie_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie(
          {
            name: 'cookie1',
            value: '1',
          },
          {
            name: 'cookie2',
            value: '2',
          },
          {
            name: 'cookie3',
            value: '3',
          }
        )
        expect(page.evaluate('document.cookie')).to eq('cookie1=1; cookie2=2; cookie3=3')
        page.delete_cookie(name: 'cookie2')
        expect(page.evaluate('document.cookie')).to eq('cookie1=1; cookie3=3')
      end
    end

    it 'should not delete cookie for different domain' do
      with_cookie_state do |page:, server:, browser:, **|
        cookie_destination_url = 'https://example.com'
        cookie_name = 'some_cookie_name'

        page.goto(server.empty_page)
        page.set_cookie(name: cookie_name, value: 'local page cookie value')
        expect(page.cookies.length).to eq(1)

        page.set_cookie(
          url: cookie_destination_url,
          name: cookie_name,
          value: 'COOKIE_DESTINATION_URL cookie value'
        )
        expect(page.cookies(cookie_destination_url).length).to eq(1)

        page.delete_cookie(name: cookie_name)

        expect(page.cookies.length).to eq(0)

        expect_cookie_equals(page.cookies(cookie_destination_url), [
          {
            name: cookie_name,
            value: 'COOKIE_DESTINATION_URL cookie value',
            domain: 'example.com',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 51,
            httpOnly: false,
            session: true,
            sourceScheme: 'Secure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should delete cookie for specified URL' do
      with_cookie_state do |page:, server:, browser:, **|
        cookie_destination_url = 'https://example.com'
        cookie_name = 'some_cookie_name'

        page.goto(server.empty_page)
        page.set_cookie(name: cookie_name, value: 'some_cookie_value')
        expect(page.cookies.length).to eq(1)

        page.set_cookie(
          url: cookie_destination_url,
          name: cookie_name,
          value: 'another_cookie_value'
        )
        expect(page.cookies(cookie_destination_url).length).to eq(1)

        page.delete_cookie(url: cookie_destination_url, name: cookie_name)

        expect(page.cookies(cookie_destination_url).length).to eq(0)

        expect_cookie_equals(page.cookies, [
          {
            name: cookie_name,
            value: 'some_cookie_value',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            size: 33,
            httpOnly: false,
            secure: false,
            session: true,
            sourceScheme: 'NonSecure',
          },
        ], chrome: browser.user_agent.include?("Chrome"))
      end
    end

    it 'should delete cookie for specified URL regardless of the current page' do
      with_cookie_state do |page:, server:, browser:, **|
        unless browser.user_agent.include?("Chrome")
          pending 'Firefox partitions cookies by top-level site'
          raise 'Firefox partitions cookies by top-level site'
        end

        cookie_destination_url = 'https://example.com'
        cookie_name = 'some_cookie_name'
        url_1 = server.empty_page
        url_2 = "#{server.cross_process_prefix}/empty.html"

        page.goto(url_1)
        page.set_cookie(
          url: cookie_destination_url,
          name: cookie_name,
          value: 'Cookie from URL_1'
        )
        expect(page.cookies(cookie_destination_url).length).to eq(1)

        page.goto(url_2)
        page.set_cookie(
          url: cookie_destination_url,
          name: cookie_name,
          value: 'Cookie from URL_2'
        )
        expect(page.cookies(cookie_destination_url).length).to eq(1)

        page.delete_cookie(name: cookie_name, url: cookie_destination_url)
        expect(page.cookies(cookie_destination_url).length).to eq(0)

        page.goto(server.empty_page)
        expect(page.cookies(cookie_destination_url).length).to eq(0)
      end
    end

    it 'should only delete cookie from the default partition if partitionkey is not specified' do
      with_cookie_state do |page:, server:, **|
        origin = origin_for(server.empty_page)
        page.goto(server.empty_page)
        page.set_cookie(
          url: page.url,
          name: 'partitionCookie',
          value: 'partition',
          secure: true,
          partitionKey: origin
        )
        expect(page.cookies.length).to eq(1)
        page.delete_cookie(url: page.url, name: 'partitionCookie')
        expect(page.cookies.length).to eq(0)
      end
    end

    it 'should delete cookie with partition key if partition key is specified' do
      with_cookie_state do |page:, server:, **|
        origin = origin_for(server.empty_page)
        page.goto(server.empty_page)
        page.set_cookie(
          url: page.url,
          name: 'partitionCookie',
          value: 'partition',
          secure: true,
          partitionKey: origin
        )
        expect(page.cookies.length).to eq(1)
        page.delete_cookie(url: page.url, name: 'partitionCookie', partitionKey: origin)
        expect(page.cookies.length).to eq(0)
      end
    end
  end
end

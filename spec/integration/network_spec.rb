# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Network" do # rubocop:disable Metrics/BlockLength
  describe "Page.authenticate" do
    it "should work" do
      with_test_state do |page:, server:, **|
        server.set_auth("/empty.html", "user", "pass")
        requests = []
        page.on(:request) { |request| requests << request if request.url == server.empty_page }
        page.authenticate(username: "user", password: "pass")

        response = page.goto(server.empty_page)

        expect(response.status).to eq(200)
        expect(requests.map(&:url)).to eq([server.empty_page, server.empty_page])
        expect(response.request.redirect_chain.length).to eq(1)
      end
    end

    it "should work with interception" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue } # rubocop:disable Style/SymbolProc
        server.set_auth("/empty.html", "user", "pass")
        page.authenticate(username: "user", password: "pass")

        response = page.goto(server.empty_page)

        expect(response.status).to eq(200)
      end
    end

    it "should error if authentication is required but not enabled" do
      with_test_state do |page:, server:, browser:, **|
        path = "/auth-not-enabled"
        url = "#{server.cross_process_prefix}#{path}"
        server.set_auth(path, "user", "pass")

        # Firefox leaves a top-level navigation pending while its native auth prompt is open.
        # A subresource exposes the same 401 response without blocking the test.
        response_promise = Async::Promise.new
        page.on(:response) do |response|
          response_promise.resolve(response) if response.url == url && !response_promise.resolved?
        end
        page.set_content("<img src=\"#{url}\">", wait_until: "domcontentloaded")
        response = Puppeteer::Bidi::AsyncUtils.async_timeout(1_000, response_promise).wait
        expect(response.status).to eq(401)

        page.close
        page = browser.new_page
        page.authenticate(username: "user", password: "pass")
        response = page.goto(url)
        expect(response.status).to eq(200)
      ensure
        page.close unless page.closed?
      end
    end

    it "should fail if credentials are wrong" do
      with_test_state do |page:, server:, **|
        path = "/auth-wrong-credentials"
        server.set_auth(path, "user2", "pass2")
        page.authenticate(username: "foo", password: "bar")

        response = page.goto("#{server.cross_process_prefix}#{path}")

        expect(response.status).to eq(401)
      end
    end

    it "should allow disabling authentication" do
      with_test_state do |page:, server:, **|
        local_path = "/auth-enabled"
        cross_process_path = "/auth-disabled"
        server.set_auth(local_path, "user3", "pass3")
        server.set_auth(cross_process_path, "user3", "pass3")
        page.authenticate(username: "user3", password: "pass3")

        response = page.goto("#{server.prefix}#{local_path}")
        expect(response.status).to eq(200)

        page.authenticate(nil)
        url = "#{server.cross_process_prefix}#{cross_process_path}"
        # Use a different origin to avoid the browser's credential cache, as upstream does.
        # Loading it as a subresource avoids Firefox's blocking native auth prompt.
        response_promise = Async::Promise.new
        page.on(:response) do |candidate|
          response_promise.resolve(candidate) if candidate.url == url && !response_promise.resolved?
        end
        page.set_content("<img src=\"#{url}\">", wait_until: "domcontentloaded")
        response = Puppeteer::Bidi::AsyncUtils.async_timeout(1_000, response_promise).wait
        expect(response.status).to eq(401)
      end
    end
  end

  it "should emit every request in a redirect chain once" do
    with_test_state do |page:, server:, **|
      server.set_redirect("/redirect-once", "/empty.html")
      requests = []
      page.on(:request) do |request|
        requests << request if request.url.end_with?("/redirect-once", "/empty.html")
      end

      response = page.goto("#{server.prefix}/redirect-once")

      expect(requests.map(&:url)).to eq(["#{server.prefix}/redirect-once", server.empty_page])
      expect(response.request.redirect_chain.map(&:url)).to eq(["#{server.prefix}/redirect-once"])
    end
  end
end # rubocop:enable Metrics/BlockLength

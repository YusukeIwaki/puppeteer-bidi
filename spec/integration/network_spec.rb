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

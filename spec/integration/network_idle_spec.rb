# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Page#wait_for_network_idle' do
  example 'waits for network to be idle' do
    with_test_state do |page:, server:, **|
      # Navigate to a page
      page.goto("#{server.prefix}/networkidle.html")

      # Wait for network idle (should complete immediately since page is loaded)
      expect do
        page.wait_for_network_idle(idle_time: 100, timeout: 5000, concurrency: 0)
      end.not_to raise_error
    end
  end

  example 'waits for network idle after triggering requests' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/networkidle.html")

      # Trigger a delayed request
      page.evaluate(<<~JS)
        setTimeout(() => {
          fetch('/simple.json');
        }, 100);
      JS

      # Wait for network idle
      expect do
        page.wait_for_network_idle(idle_time: 500, timeout: 3000, concurrency: 0)
      end.not_to raise_error
    end
  end

  example "waits for a redirected request to finish" do
    with_test_state do |page:, server:, **|
      release_response = Async::Promise.new
      server.set_redirect("/network-idle-redirect", "/network-idle-target")
      server.set_route("/network-idle-target") do |_request, writer|
        release_response.wait
        writer.write("done")
        writer.finish
      end
      page.goto(server.empty_page)

      idle_finished = false
      idle_task = Async do
        page.wait_for_network_idle(idle_time: 100, timeout: 3000, concurrency: 0)
        idle_finished = true
      end
      target_request = Async { server.wait_for_request("/network-idle-target") }
      page.evaluate("url => { void fetch(url); }", "#{server.prefix}/network-idle-redirect")

      target_request.wait
      sleep(0.2)
      expect(idle_finished).to eq(false)

      release_response.resolve(nil)
      idle_task.wait
      expect(idle_finished).to eq(true)
    end
  end

  example 'wait_for_navigation with networkidle0' do
    with_test_state do |page:, server:, **|
      # Navigate with networkidle0
      response = page.wait_for_navigation(wait_until: 'networkidle0', timeout: 5000) do
        page.evaluate("window.location.href = '#{server.prefix}/networkidle.html'")
      end

      expect(response).to be_a(Puppeteer::Bidi::HTTPResponse)
      expect(page.url).to include('networkidle.html')
    end
  end

  example 'wait_for_navigation with networkidle2' do
    with_test_state do |page:, server:, **|
      # Navigate with networkidle2
      response = page.wait_for_navigation(wait_until: 'networkidle2', timeout: 5000) do
        page.evaluate("window.location.href = '#{server.prefix}/networkidle.html'")
      end

      expect(response).to be_a(Puppeteer::Bidi::HTTPResponse)
      expect(page.url).to include('networkidle.html')
    end
  end

  example 'wait_for_navigation with array of wait conditions' do
    with_test_state do |page:, server:, **|
      # Navigate with multiple conditions
      response = page.wait_for_navigation(wait_until: ['load', 'networkidle0'], timeout: 5000) do
        page.evaluate("window.location.href = '#{server.prefix}/networkidle.html'")
      end

      expect(response).to be_a(Puppeteer::Bidi::HTTPResponse)
      expect(page.url).to include('networkidle.html')
    end
  end
end

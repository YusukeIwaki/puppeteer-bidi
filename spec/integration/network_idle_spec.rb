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

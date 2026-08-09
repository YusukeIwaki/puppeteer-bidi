# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Browser' do
  describe "target events" do
    it "should work" do
      with_test_state do |browser:, server:, **|
        events = []
        target_created_listener = proc do |target|
          events << "CREATED: #{target.url}"
        end
        target_changed_listener = proc do |target|
          events << "CHANGED: #{target.url}"
        end
        target_destroyed_listener = proc do |target|
          events << "DESTROYED: #{target.url}"
        end
        browser.on(:targetcreated, &target_created_listener)
        browser.on(:targetchanged, &target_changed_listener)
        browser.on(:targetdestroyed, &target_destroyed_listener)

        page = browser.new_page
        page.goto(server.empty_page)
        page.close

        expect(events).to eq(
          [
            "CREATED: about:blank",
            "CHANGED: #{server.empty_page}",
            "DESTROYED: #{server.empty_page}"
          ]
        )
      ensure
        page&.close unless page&.closed?
        browser&.off(:targetcreated, &target_created_listener) if target_created_listener
        browser&.off(:targetchanged, &target_changed_listener) if target_changed_listener
        browser&.off(:targetdestroyed, &target_destroyed_listener) if target_destroyed_listener
      end
    end

    it "should support one-time and removable listeners" do
      with_test_state do |browser:, **|
        created_urls = []
        removed_urls = []
        once_listener = proc { |target| created_urls << target.url }
        removed_listener = proc { |target| removed_urls << target.url }

        browser.once(:targetcreated, &once_listener)
        browser.on(:targetcreated, &removed_listener)
        browser.off(:targetcreated, &removed_listener)

        pages = [browser.new_page, browser.new_page]

        expect(created_urls).to eq(["about:blank"])
        expect(removed_urls).to be_empty
      ensure
        pages&.each { |page| page.close unless page.closed? }
        browser&.off(:targetcreated, &removed_listener) if removed_listener
      end
    end

    it "should dispose target listeners when closed" do
      with_browser do |browser|
        emitter = browser.instance_variable_get(:@emitter)
        browser.on(:targetcreated) { |_target| }

        browser.close

        expect(emitter).to be_disposed
      end
    end

    it "should dispose target listeners when disconnected" do
      with_browser do |browser|
        emitter = browser.instance_variable_get(:@emitter)
        browser.on(:targetcreated) { |_target| }

        browser.disconnect

        expect(emitter).to be_disposed
      end
    end
  end

  describe 'targets' do
    it 'returns browser and page targets' do
      with_test_state do |browser:, page:, context:, **|
        targets = browser.targets

        expect(targets.map(&:type)).to include('browser', 'page')
        expect(targets).to include(browser.target)
        expect(targets).to include(page.target)
        expect(context.targets).to include(page.target)
        expect(page.target.page).to eq(page)
        expect(page.target.as_page).to eq(page)
        expect(page.target).to equal(page.target)
      end
    end

    it 'returns frame targets' do
      with_test_state do |browser:, page:, context:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")

        frame = page.frames.find { |candidate| candidate != page.main_frame }
        frame_target = context.targets.find { |target| target.is_a?(Puppeteer::Bidi::FrameTarget) }

        expect(frame).not_to be_nil
        expect(frame_target).not_to be_nil
        expect(frame_target.page).to eq(page)
        expect(frame_target.as_page).to eq(page)
        expect(frame_target.url).to eq(frame.url)
        expect(browser.targets).to include(frame_target)
        expect(context.wait_for_target { |target| target == frame_target }).to equal(frame_target)
      end
    end

    it 'waits for a context target' do
      with_test_state do |context:, **|
        page = nil
        begin
          page = context.new_page
          target = context.wait_for_target { |candidate| candidate.page == page }

          expect(target).to equal(page.target)
        ensure
          page&.close unless page&.closed?
        end
      end
    end
  end

  describe 'Browser.get_window_bounds / Browser.set_window_bounds' do
    it 'should get and set window bounds for a window page' do
      pending "Firefox BiDi adjusts window position bounds in headful mode on macOS" if mac? && !headless_mode?

      with_test_state do |browser:, context:, **|
        page = nil
        begin
          page = context.new_page(type: 'window')

          window_id = page.window_id
          expect(window_id).to be_a(String)
          expect(window_id).not_to be_empty

          initial_bounds = { left: 10, top: 20, width: 800, height: 600 }
          browser.set_window_bounds(window_id, initial_bounds)
          expect(browser.get_window_bounds(window_id)).to include(initial_bounds)

          updated_bounds = { left: 100, top: 200, width: 1600, height: 1200 }
          browser.set_window_bounds(window_id, updated_bounds)
          expect(browser.get_window_bounds(window_id)).to include(updated_bounds)

          browser.set_window_bounds(window_id, { window_state: 'maximized' })
          expect(browser.get_window_bounds(window_id)[:window_state]).to eq('maximized')
        rescue Puppeteer::Bidi::Connection::ProtocolError => error
          pending "Window management is not supported by this browser: #{error.message}"
          raise error
        ensure
          page&.close unless page&.closed?
        end
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

test("[Browser][targets] returns browser and page targets") do |browser:, page:, context:|
  targets = browser.targets

  expect(targets.map(&:type)).to include_all("browser", "page")
  expect(targets).to include(browser.target)
  expect(targets).to include(page.target)
  expect(context.targets).to include(page.target)
  expect(page.target.page).to eq(page)
  expect(page.target.as_page).to eq(page)
  expect(page.target).to be_equal(page.target)
end

test("[Browser][targets] returns frame targets") do |browser:, page:, context:, server:|
  page.goto("#{server.prefix}/frames/one-frame.html")

  frame = page.frames.find { |candidate| candidate != page.main_frame }
  frame_target = context.targets.find { |target| target.is_a?(Puppeteer::Bidi::FrameTarget) }

  expect(frame).not_to be_nil
  expect(frame_target).not_to be_nil
  expect(frame_target.page).to eq(page)
  expect(frame_target.as_page).to eq(page)
  expect(frame_target.url).to eq(frame.url)
  expect(browser.targets).to include(frame_target)
  expect(context.wait_for_target { |target| target == frame_target }).to be_equal(frame_target)
end

test("[Browser][targets] waits for a context target") do |context:|
  page = nil
  begin
    page = context.new_page
    target = context.wait_for_target { |candidate| candidate.page == page }

    expect(target).to be_equal(page.target)
  ensure
    page&.close unless page&.closed?
  end
end

test("[Browser][Browser.get_window_bounds / Browser.set_window_bounds] should get and set window bounds for a window page") do |browser:, context:|
  page = nil
  begin
    page = context.new_page(type: "window")

    window_id = page.window_id
    expect(window_id).to be_a(String)
    expect(window_id).not_to be_empty

    initial_bounds = { left: 10, top: 20, width: 800, height: 600 }
    browser.set_window_bounds(window_id, initial_bounds)
    expect(browser.get_window_bounds(window_id)).to include_all(initial_bounds)

    updated_bounds = { left: 100, top: 200, width: 1600, height: 1200 }
    browser.set_window_bounds(window_id, updated_bounds)
    expect(browser.get_window_bounds(window_id)).to include_all(updated_bounds)

    browser.set_window_bounds(window_id, { window_state: "maximized" })
    expect(browser.get_window_bounds(window_id)[:window_state]).to eq("maximized")
  rescue Puppeteer::Bidi::Connection::ProtocolError => error
    pending "Window management is not supported by this browser: #{error.message}"
    raise error
  ensure
    page&.close unless page&.closed?
  end
end

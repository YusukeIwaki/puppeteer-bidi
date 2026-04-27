# frozen_string_literal: true

require "test_helper"

test("[Page.goBack] should work") do |page:, server:|
  page.goto(server.empty_page)
  page.goto("#{server.prefix}/grid.html")

  response = page.go_back
  expect(response).not_to be_nil
  expect(response.ok?).to eq(true)
  expect(response.url).to include(server.empty_page)

  response = page.go_forward
  expect(response).not_to be_nil
  expect(response.ok?).to eq(true)
  expect(response.url).to include("/grid.html")

  response = page.go_forward
  expect(response).to be_nil
end

test("[Page.goBack] should work with HistoryAPI") do |page:, server:|
  page.goto(server.empty_page)
  page.evaluate(<<~JS)
    () => {
      history.pushState({}, '', '/first.html');
      history.pushState({}, '', '/second.html');
    }
  JS

  expect(page.url).to eq("#{server.prefix}/second.html")

  response = page.go_back
  expect(response).to be_nil
  expect(page.url).to eq("#{server.prefix}/first.html")

  page.go_back
  expect(page.url).to eq(server.empty_page)

  response = page.go_forward
  expect(response).to be_nil
  expect(page.url).to eq("#{server.prefix}/first.html")
end

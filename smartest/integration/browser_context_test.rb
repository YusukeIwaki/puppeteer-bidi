# frozen_string_literal: true

require "test_helper"

def permission_state(page, name)
  page.evaluate(<<~JS, name)
    permissionName => {
      return navigator.permissions.query({name: permissionName}).then(result => {
        return result.state;
      });
    }
  JS
end

test("[BrowserContext][BrowserContext.new_page] should create a background page") do |context:|
  page = nil
  begin
    page = context.new_page(background: true)
    expect(page.evaluate("() => document.visibilityState")).to eq("hidden")
  rescue Puppeteer::Bidi::Connection::ProtocolError => error
    pending "Background page creation is not supported by this browser: #{error.message}"
    raise error
  ensure
    page&.close unless page&.closed?
  end
end

test("[BrowserContext][BrowserContext.set_permission] should set permission state for an origin") do |page:, context:, server:|
  page.goto(server.empty_page)

  context.set_permission(server.empty_page, {
    permission: { name: "geolocation" },
    state: "granted"
  })
  expect(permission_state(page, "geolocation")).to eq("granted")

  context.set_permission(server.empty_page, {
    permission: { name: "geolocation" },
    state: "denied"
  })
  expect(permission_state(page, "geolocation")).to eq("denied")

  context.set_permission(server.empty_page, {
    permission: { name: "geolocation" },
    state: "prompt"
  })
  expect(permission_state(page, "geolocation")).to eq("prompt")
end

test("[BrowserContext][BrowserContext.set_permission] should reject wildcard origin") do |context:|
  expect {
    context.set_permission("*", {
      permission: { name: "geolocation" },
      state: "granted"
    })
  }.to raise_error(Puppeteer::Bidi::UnsupportedOperationError, /Origin \(\*\) is not supported/)
end

test("[BrowserContext][BrowserContext.set_permission] should support multiple permissions") do |page:, context:, server:|
  page.goto(server.empty_page)

  begin
    context.set_permission(
      server.empty_page,
      { permission: { name: "geolocation" }, state: "granted" },
      { permission: { name: "midi" }, state: "granted" }
    )
    expect(permission_state(page, "geolocation")).to eq("granted")
    expect(permission_state(page, "midi")).to eq("granted")

    context.set_permission(
      server.empty_page,
      { permission: { name: "geolocation" }, state: "denied" },
      { permission: { name: "midi" }, state: "denied" }
    )
    expect(permission_state(page, "geolocation")).to eq("denied")
    expect(permission_state(page, "midi")).to eq("denied")

    context.set_permission(
      server.empty_page,
      { permission: { name: "geolocation" }, state: "prompt" },
      { permission: { name: "midi" }, state: "prompt" }
    )
    expect(permission_state(page, "geolocation")).to eq("prompt")
    expect(permission_state(page, "midi")).to eq("prompt")
  rescue StandardError => error
    pending "Multiple permission override is not supported by this browser: #{error.message}"
    raise error
  end
end

test("[BrowserContext][Browser.set_permission] should set permission state in the default browser context") do |page:, browser:, server:|
  page.goto(server.empty_page)

  browser.set_permission(server.empty_page, {
    permission: { name: "geolocation" },
    state: "granted"
  })
  expect(permission_state(page, "geolocation")).to eq("granted")

  browser.set_permission(server.empty_page, {
    permission: { name: "geolocation" },
    state: "denied"
  })
  expect(permission_state(page, "geolocation")).to eq("denied")

  browser.set_permission(server.empty_page, {
    permission: { name: "geolocation" },
    state: "prompt"
  })
  expect(permission_state(page, "geolocation")).to eq("prompt")
end

test("[BrowserContext][BrowserContext.clear_permission_overrides] should reset override_permissions back to prompt") do |page:, context:, server:|
  page.goto(server.empty_page)
  expect(permission_state(page, "geolocation")).to eq("prompt")

  context.override_permissions(server.empty_page, ["geolocation"])
  expect(permission_state(page, "geolocation")).to eq("granted")

  context.clear_permission_overrides
  expect(permission_state(page, "geolocation")).to eq("prompt")
end

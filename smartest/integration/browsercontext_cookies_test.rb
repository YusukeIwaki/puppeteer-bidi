# frozen_string_literal: true

require "test_helper"

def with_cookie_state(browser)
  context = browser.create_browser_context
  page = context.new_page

  begin
    yield(page, context)
  ensure
    page.close unless page.closed?
    context.close
  end
end

test("[BrowserContext cookies][BrowserContext.cookies] should find no cookies in new context") do |browser:|
  with_cookie_state(browser) do |_page, context|
    expect(context.cookies).to eq([])
  end
end

test("[BrowserContext cookies][BrowserContext.cookies] should find cookie created in page") do |browser:, server:|
  with_cookie_state(browser) do |page, context|
    page.goto(server.empty_page)
    page.evaluate("document.cookie = 'infoCookie = secret'")
    expect_cookie_equals(context.cookies, [
      {
        name: "infoCookie",
        value: "secret",
        domain: "localhost",
        path: "/",
        sameParty: false,
        expires: -1,
        size: 16,
        httpOnly: false,
        secure: false,
        session: true,
        sourceScheme: "NonSecure",
      },
    ], chrome: browser.user_agent.include?("Chrome"))
  end
end

test("[BrowserContext cookies][BrowserContext.cookies] should find partitioned cookie") do |browser:|
  with_cookie_state(browser) do |_page, context|
    top_level_site = "https://example.test"
    is_chrome = browser.user_agent.include?("Chrome")
    context.set_cookie(
      name: "infoCookie",
      value: "secret",
      domain: URI.parse(top_level_site).host,
      path: "/",
      sameParty: false,
      expires: -1,
      httpOnly: false,
      secure: true,
      partitionKey: is_chrome ? {
        sourceOrigin: top_level_site,
        hasCrossSiteAncestor: false,
      } : {
        sourceOrigin: top_level_site,
      }
    )
    cookies = context.cookies
    expect(cookies.length).to eq(1)
    if is_chrome
      expect(cookies[0]["partitionKey"]).to eq({
        "sourceOrigin" => top_level_site,
        "hasCrossSiteAncestor" => false,
      })
    else
      expect(cookies[0]["partitionKey"]).to be_nil
    end
  end
end

test('[BrowserContext cookies][BrowserContext.cookies] should properly report "Default" sameSite cookie') do |browser:, server:|
  with_cookie_state(browser) do |page, context|
    page.goto(server.empty_page)
    name = "defaultSameSite"
    context.set_cookie(
      name: name,
      value: "b",
      domain: "localhost",
      sameSite: "Default"
    )

    cookies = context.cookies
    cookie = cookies.find { |entry| entry["name"] == name }
    expect(cookie).not_to be_nil
    expect(["Default", "Lax", nil]).to include(cookie["sameSite"])
    context.delete_matching_cookies(name: name, domain: "localhost")
  end
end

test("[BrowserContext cookies][BrowserContext.set_cookie] should set with undefined partition key") do |browser:, server:|
  with_cookie_state(browser) do |page, context|
    context.set_cookie(
      name: "infoCookie",
      value: "secret",
      domain: "localhost",
      path: "/",
      sameParty: false,
      expires: -1,
      httpOnly: false,
      secure: false,
      sourceScheme: "NonSecure"
    )

    page.goto(server.empty_page)

    expect(page.evaluate("document.cookie")).to eq("infoCookie=secret")
  end
end

test("[BrowserContext cookies][BrowserContext.set_cookie] should set cookie with a partition key") do |browser:, https_server:|
  with_cookie_state(browser) do |page, context|
    url = URI.parse(https_server.empty_page)
    origin = "#{url.scheme}://#{url.host}"
    origin = "#{origin}:#{url.port}" if url.port && url.port != 443
    is_chrome = browser.user_agent.include?("Chrome")
    context.set_cookie(
      name: "infoCookie",
      value: "secret",
      domain: url.host,
      secure: true,
      partitionKey: is_chrome ? {
        sourceOrigin: origin.sub(/:\d+\z/, ""),
        hasCrossSiteAncestor: false,
      } : {
        sourceOrigin: origin,
      }
    )

    page.goto(url.to_s)

    expect(page.evaluate("document.cookie")).to eq("infoCookie=secret")
  end
end

test("[BrowserContext cookies][BrowserContext.delete_cookie] should delete cookies") do |browser:, server:|
  with_cookie_state(browser) do |page, context|
    page.goto(server.empty_page)
    context.set_cookie(
      {
        name: "cookie1",
        value: "1",
        domain: "localhost",
        path: "/",
        sameParty: false,
        expires: -1,
        httpOnly: false,
        secure: false,
        sourceScheme: "NonSecure",
      },
      {
        name: "cookie2",
        value: "2",
        domain: "localhost",
        path: "/",
        sameParty: false,
        expires: -1,
        httpOnly: false,
        secure: false,
        sourceScheme: "NonSecure",
      }
    )
    expect(page.evaluate("document.cookie")).to eq("cookie1=1; cookie2=2")
    context.delete_cookie(
      name: "cookie1",
      value: "1",
      domain: "localhost",
      path: "/",
      sameParty: false,
      expires: -1,
      size: 16,
      httpOnly: false,
      secure: false,
      session: true,
      sourceScheme: "NonSecure"
    )
    expect(page.evaluate("document.cookie")).to eq("cookie2=2")
  end
end

test('[BrowserContext cookies][BrowserContext.delete_cookie] should be able to delete "Default" sameSite cookie') do |browser:, server:|
  with_cookie_state(browser) do |page, context|
    page.goto(server.empty_page)
    name = "deleteDefaultSameSite"
    context.set_cookie(
      name: name,
      value: "b",
      domain: "localhost",
      sameSite: "Default"
    )

    cookies = context.cookies
    expect(cookies.find { |entry| entry["name"] == name }).not_to be_nil
    context.delete_matching_cookies(name: name, domain: "localhost")
    cookies_after = context.cookies
    expect(cookies_after.find { |entry| entry["name"] == name }).to be_nil
  end
end

test("[BrowserContext cookies][BrowserContext.delete_matching_cookies] should delete cookies matching filters") do |browser:, server:|
  filters = [
    {
      name: "cookie1",
    },
    {
      url: "https://example.test/test",
      name: "cookie1",
    },
    {
      domain: "example.test",
      name: "cookie1",
    },
    {
      path: "/test",
      name: "cookie1",
    },
    {
      name: "cookie1",
      partitionKey: {
        sourceOrigin: "https://example.test",
      },
    },
  ]

  filters.each do |filter|
    with_cookie_state(browser) do |page, context|
      page.goto(server.empty_page)
      expect(context.cookies.length).to eq(0)
      top_level_site = "https://example.test"
      is_chrome = browser.user_agent.include?("Chrome")
      context.set_cookie(
        {
          name: "cookie1",
          value: "secret",
          domain: URI.parse(top_level_site).host,
          path: "/test",
          sameParty: false,
          expires: -1,
          httpOnly: false,
          secure: true,
          partitionKey: is_chrome ? {
            sourceOrigin: top_level_site,
            hasCrossSiteAncestor: false,
          } : nil,
        },
        {
          name: "cookie2",
          value: "secret",
          domain: URI.parse(top_level_site).host,
          path: "/test",
          sameParty: false,
          expires: -1,
          httpOnly: false,
          secure: true,
          partitionKey: is_chrome ? {
            sourceOrigin: top_level_site,
            hasCrossSiteAncestor: false,
          } : nil,
        }
      )
      expect(context.cookies.length).to eq(2)
      context.delete_matching_cookies(filter)
      cookies = context.cookies
      expect(cookies.length).to eq(1)
      expect(cookies[0]["name"]).to eq("cookie2")
    end
  end
end

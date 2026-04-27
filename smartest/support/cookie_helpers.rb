# frozen_string_literal: true

module CookieHelpers
  STANDARD_COOKIE_KEYS = %w[domain expires httpOnly name path secure session size value].freeze

  def expect_cookie_equals(cookies, expected_cookies, chrome: false)
    normalized_expected = expected_cookies.map do |cookie|
      normalized = cookie.transform_keys(&:to_s)
      next normalized if chrome

      normalized.select { |key, _| STANDARD_COOKIE_KEYS.include?(key) }
    end

    expect(cookies.length).to eq(normalized_expected.length)
    cookies.each_with_index do |cookie, index|
      expected = normalized_expected[index]
      expected.each do |key, value|
        expect(cookie[key]).to eq(value)
      end
    end
  end
end

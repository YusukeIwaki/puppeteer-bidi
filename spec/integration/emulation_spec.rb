# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Emulation" do
  describe "Page.emulate_locale" do
    it "should work" do
      with_test_state do |page:, **|
        default_locale = page.evaluate("() => Intl.NumberFormat().resolvedOptions().locale")
        default_language = page.evaluate("() => navigator.language")

        page.emulate_locale("de-DE")
        expect(page.evaluate("() => Intl.NumberFormat().resolvedOptions().locale")).to eq("de-DE")
        expect(page.evaluate("() => new Intl.NumberFormat().format(123456.78)")).to eq("123.456,78")
        expect(page.evaluate("() => navigator.language")).to eq("de-DE")
        expect(page.evaluate("() => navigator.languages[0]")).to eq("de-DE")

        page.emulate_locale("fr-FR")
        expect(page.evaluate("() => Intl.DateTimeFormat().resolvedOptions().locale")).to eq("fr-FR")

        page.emulate_locale
        expect(page.evaluate("() => Intl.NumberFormat().resolvedOptions().locale")).to eq(default_locale)
        expect(page.evaluate("() => navigator.language")).to eq(default_language)
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::PSelectorParser do
  describe ".parse_p_selectors" do
    it "parses nested selectors" do
      expect(described_class.parse_p_selectors("& > div")).to eq(
        [
          [[["&>div"]]],
          true,
          false,
          false,
        ]
      )
    end

    it "parses nested selectors with p-selector syntax" do
      expect(described_class.parse_p_selectors("& >>> div")).to eq(
        [
          [[["&"], ">>>", ["div"]]],
          false,
          false,
          false,
        ]
      )
    end

    it "parses selectors with pseudo classes" do
      expect(described_class.parse_p_selectors("&:is(div)")).to eq(
        [
          [[["&:is(div)"]]],
          true,
          true,
          false,
        ]
      )
    end

    it "parses nested selectors with pseudo classes and p-selector syntax" do
      expect(described_class.parse_p_selectors("&:is(div) >>> span:is(div)")).to eq(
        [
          [[["&:is(div)"], ">>>", ["span:is(div)"]]],
          false,
          true,
          false,
        ]
      )
    end

    it "returns false if no aria query is present" do
      selectors, _, _, has_aria = described_class.parse_p_selectors("::-p-aria(Text)")

      expect(selectors).to eq([[[{ name: "aria", value: "Text" }]]])
      expect(has_aria).to be(true)
    end

    it "returns true if an aria query is present" do
      selectors, _, _, has_aria = described_class.parse_p_selectors('::-p-aria([name="a"i])')

      expect(selectors).to eq([[[{ name: "aria", value: '[name="a"i]' }]]])
      expect(has_aria).to be(true)
    end
  end
end

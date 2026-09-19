# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::PSelectorParser do
  describe ".parse_p_selectors" do
    it "parses nested selectors" do
      updated_selector, is_pure_css, has_pseudo_classes =
        described_class.parse_p_selectors("& > div")

      expect(updated_selector).to eq([[["&>div"]]])
      expect(is_pure_css).to be(true)
      expect(has_pseudo_classes).to be(false)
    end

    it "parses nested selectors with p-selector syntax" do
      updated_selector, is_pure_css, has_pseudo_classes =
        described_class.parse_p_selectors("& > div >>> button")

      expect(updated_selector).to eq([[["&>div"], ">>>", ["button"]]])
      expect(is_pure_css).to be(false)
      expect(has_pseudo_classes).to be(false)
    end

    it "parses selectors with pseudo classes" do
      updated_selector, is_pure_css, has_pseudo_classes =
        described_class.parse_p_selectors("div:focus")

      expect(updated_selector).to eq([[["div:focus"]]])
      expect(is_pure_css).to be(true)
      expect(has_pseudo_classes).to be(true)
    end

    it "parses nested selectors with pseudo classes and p-selector syntax" do
      updated_selector, is_pure_css, has_pseudo_classes =
        described_class.parse_p_selectors("& > div:focus >>>> button:focus")

      expect(updated_selector).to eq([[["&>div:focus"], ">>>>", ["button:focus"]]])
      expect(is_pure_css).to be(false)
      expect(has_pseudo_classes).to be(true)
    end

    describe "hasAria" do
      it "returns false if no aria query is present" do
        _, _, _, has_aria = described_class.parse_p_selectors("div:focus")

        expect(has_aria).to be(false)
      end

      it "returns true if an aria query is present" do
        _, _, _, has_aria = described_class.parse_p_selectors(
          "div:focus >>> ::-p-aria(Text)"
        )

        expect(has_aria).to be(true)
      end
    end

    # Supplementary regression coverage beyond the upstream cases above.
    it "parses namespaced type selectors" do
      updated_selector, is_pure_css, _, _ =
        described_class.parse_p_selectors("svg|div >>> h1")

      expect(updated_selector).to eq([[["svg|div"], ">>>", ["h1"]]])
      expect(is_pure_css).to be(false)
    end

    it "parses -p-aria values with quotes" do
      selectors, _, _, has_aria =
        described_class.parse_p_selectors('::-p-aria([name="a"i])')

      expect(selectors).to eq([[[{ name: "aria", value: '[name="a"i]' }]]])
      expect(has_aria).to be(true)
    end
  end
end

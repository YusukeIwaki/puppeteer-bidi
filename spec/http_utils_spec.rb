# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::HTTPUtils do
  describe ".normalize_header_value" do
    it "gives single-line header value unchanged" do
      header = "application/json; charset=utf-8"
      result = described_class.normalize_header_value(header)

      expect(result).to eq(header)
    end

    it "normalizes multiline header with newlines" do
      header = "text/html;\n charset=utf-8;\n boundary=something"
      result = described_class.normalize_header_value(header)

      expect(result).to eq("text/html;, charset=utf-8;, boundary=something")
    end

    it "trims whitespace from each line" do
      header = "text/html; \n  charset=utf-8  \n   boundary=something   "
      result = described_class.normalize_header_value(header)

      expect(result).to eq("text/html;, charset=utf-8, boundary=something")
    end

    it "filters out empty lines" do
      header = "text/html;\n\n charset=utf-8;\n\n\n boundary=something"
      result = described_class.normalize_header_value(header)

      expect(result).to eq("text/html;, charset=utf-8;, boundary=something")
    end
  end
end

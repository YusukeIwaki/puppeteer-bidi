# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::HTTPUtils do # rubocop:disable Metrics/BlockLength
  describe ".normalize_header_value" do
    it "gives single-line header value unchanged" do
      header = "application/json; charset=utf-8"
      result = described_class.normalize_header_value("content-type", header)

      expect(result).to eq(header)
    end

    it "normalizes multiline header with newlines" do
      header = "text/html;\n charset=utf-8;\n boundary=something"
      result = described_class.normalize_header_value("content-type", header)

      expect(result).to eq("text/html;, charset=utf-8;, boundary=something")
    end

    it "trims whitespace from each line" do
      header = "text/html; \n  charset=utf-8  \n   boundary=something   "
      result = described_class.normalize_header_value("content-type", header)

      expect(result).to eq("text/html;, charset=utf-8, boundary=something")
    end

    it "filters out empty lines" do
      header = "text/html;\n\n charset=utf-8;\n\n\n boundary=something"
      result = described_class.normalize_header_value("content-type", header)

      expect(result).to eq("text/html;, charset=utf-8;, boundary=something")
    end

    it "normalizes set-cookie with newlines" do
      header = "a=b\n c=d"
      result = described_class.normalize_header_value("set-cookie", header)

      expect(result).to eq("a=b\n c=d")
    end
  end
end # rubocop:enable Metrics/BlockLength

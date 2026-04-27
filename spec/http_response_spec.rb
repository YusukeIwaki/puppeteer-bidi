# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::HTTPResponse do
  def fake_request(content)
    Class.new do
      define_method(:get_response_content) { content }
    end.new
  end

  describe "#text" do
    it "returns valid UTF-8 text" do
      response = described_class.new(
        data: { "url" => "https://example.test", "status" => 200 },
        request: fake_request("hello".b)
      )

      expect(response.text).to eq("hello")
      expect(response.text.encoding).to eq(Encoding::UTF_8)
    end

    it "raises for malformed UTF-8" do
      response = described_class.new(
        data: { "url" => "https://example.test", "status" => 200 },
        request: fake_request("\xFF".b)
      )

      expect { response.text }.to raise_error(Encoding::InvalidByteSequenceError)
    end
  end
end

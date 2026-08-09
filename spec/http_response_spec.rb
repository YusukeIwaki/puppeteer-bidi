# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::HTTPResponse do
  def string_header(name, value)
    { "name" => name, "value" => { "type" => "string", "value" => value } }
  end

  def fake_request(content)
    Class.new do
      define_method(:get_response_content) { content }
    end.new
  end

  describe "#headers" do
    it "combines duplicate set-cookie headers using a newline" do
      response = described_class.new(
        data: {
          "url" => "http://localhost/",
          "status" => 200,
          "statusText" => "OK",
          "headers" => [
            string_header("set-cookie", "a=b"),
            string_header("set-cookie", "c=d")
          ]
        },
        request: nil
      )

      expect(response.headers["set-cookie"]).to eq("a=b\n c=d")
    end

    it "combines other duplicate headers using a comma" do
      response = described_class.new(
        data: {
          "url" => "http://localhost/",
          "status" => 200,
          "statusText" => "OK",
          "headers" => [
            string_header("cache-control", "no-cache"),
            string_header("cache-control", "no-store")
          ]
        },
        request: nil
      )

      expect(response.headers["cache-control"]).to eq("no-cache, no-store")
    end
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

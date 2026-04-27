# frozen_string_literal: true

require "test_helper"

test("[Evaluation][Page.evaluate] should work") do |page:|
  result = page.evaluate(<<~JAVASCRIPT)
    () => {
      return 7 * 3;
    }
  JAVASCRIPT
  expect(result).to eq(21)
end

test("[Evaluation][Page.evaluate] should transfer NaN") do |page:|
  result = page.evaluate("(a) => a", Float::NAN)
  expect(result.nan?).to eq(true)
end

test("[Evaluation][Page.evaluate] should transfer -0") do |page:|
  result = page.evaluate("(a) => a", -0.0)
  # Ruby doesn't distinguish -0.0 from 0.0 in equality
  # but BiDi should preserve it
  expect(result).to eq(0.0)
  # Check if it's actually -0 by checking 1/result
  expect(1.0 / result).to eq(Float::INFINITY * -1)
end

test("[Evaluation][Page.evaluate] should transfer Infinity") do |page:|
  result = page.evaluate("(a) => a", Float::INFINITY)
  expect(result).to eq(Float::INFINITY)
end

test("[Evaluation][Page.evaluate] should transfer -Infinity") do |page:|
  result = page.evaluate("(a) => a", -Float::INFINITY)
  expect(result).to eq(-Float::INFINITY)
end

test("[Evaluation][Page.evaluate] should transfer arrays") do |page:|
  result = page.evaluate("(a) => a", [1, 2, 3])
  expect(result).to eq([1, 2, 3])
end

test("[Evaluation][Page.evaluate] should modify global environment") do |page:|
  page.evaluate("() => { return (globalThis.globalVar = 123); }")
  expect(page.evaluate("globalVar")).to eq(123)
end

test("[Evaluation][Page.evaluate] should await promise") do |page:|
  result = page.evaluate(<<~JAVASCRIPT)
    () => {
      return Promise.resolve(8 * 7);
    }
  JAVASCRIPT
  expect(result).to eq(56)
end

test("[Evaluation][Page.evaluate] should transfer arrays as arrays, not objects") do |page:|
  result = page.evaluate("(a) => Array.isArray(a)", [1, 2, 3])
  expect(result).to eq(true)
end

test("[Evaluation][Page.evaluate] should work with unicode chars") do |page:|
  result = page.evaluate("(a) => a['中文字符']", { "中文字符" => 42 })
  expect(result).to eq(42)
end

test("[Evaluation][Page.evaluate] should throw when evaluation throws") do |page:|
  expect {
    page.evaluate("() => { return notExistingObject.property; }")
  }.to raise_error(/notExistingObject/)
end

test("[Evaluation][Page.evaluate] should support thrown strings as error messages") do |page:|
  error = nil
  begin
    page.evaluate("() => { throw 'qwerty'; }")
  rescue => e
    error = e
  end
  expect(error).not_to be_nil
  expect(error.message).to include("qwerty")
end

test("[Evaluation][Page.evaluate] should support thrown platform objects as error messages") do |page:|
  expect do
    page.evaluate("() => { throw new DOMException('some DOMException message'); }")
  end.to raise_error(/some DOMException message/)
end

test("[Evaluation][Page.evaluate] should accept element handle as an argument") do |page:|
  page.set_content("<section>42</section>")
  element = page.query_selector("section")
  text = page.evaluate("(e) => e.textContent", element)
  expect(text).to eq("42")
end

test("[Evaluation][Page.evaluate] should return proper type for strings") do |page:|
  result = page.evaluate('() => "hello"')
  expect(result).to be_a(String)
  expect(result).to eq("hello")
end

test("[Evaluation][Page.evaluate] should return proper type for numbers") do |page:|
  result = page.evaluate("() => 42")
  expect(result).to be_a(Integer)
  expect(result).to eq(42)
end

test("[Evaluation][Page.evaluate] should return proper type for booleans") do |page:|
  result = page.evaluate("() => true")
  expect(result).to eq(true)
end

test("[Evaluation][Page.evaluate] should return undefined for objects with undefined properties") do |page:|
  result = page.evaluate("() => ({ a: undefined })")
  expect(result).to eq({ "a" => nil })
end

test("[Evaluation][Page.evaluate] should properly serialize nested objects") do |page:|
  result = page.evaluate("() => ({ a: { b: { c: 42 } } })")
  expect(result).to eq({ "a" => { "b" => { "c" => 42 } } })
end

test("[Evaluation][Page.evaluate] should properly serialize null") do |page:|
  result = page.evaluate("() => null")
  expect(result).to be_nil
end

test("[Evaluation][Page.evaluate] should properly serialize undefined") do |page:|
  result = page.evaluate("() => undefined")
  expect(result).to be_nil
end

test("[Evaluation][Page.evaluate] should transfer maps") do |page:|
  result = page.evaluate('() => { const map = new Map(); map.set("key", "value"); return map; }')
  # Maps are serialized as objects in BiDi
  expect(result).to be_a(Hash)
  expect(result["key"]).to eq("value")
end

test("[Evaluation][Frame.evaluate] should work via main_frame") do |page:|
  frame = page.main_frame
  result = frame.evaluate("() => 7 * 3")
  expect(result).to eq(21)
end

test("[Evaluation][Frame.evaluate] should transfer values correctly") do |page:|
  frame = page.main_frame
  result = frame.evaluate("(a, b) => a + b", 3, 4)
  expect(result).to eq(7)
end

test("[Evaluation][Page.evaluateOnNewDocument] should evaluate before anything else on the page") do |page:, server:|
  page.evaluate_on_new_document(<<~JS)
    () => {
      globalThis.injected = 123;
    }
  JS
  page.goto("#{server.prefix}/tamperable.html")
  result = page.evaluate("() => globalThis.result")
  expect(result).to eq(123)
end

test("[Evaluation][Page.evaluateOnNewDocument] should work with CSP") do |page:, server:|
  server.set_csp("/empty.html", "script-src #{server.prefix}")
  page.evaluate_on_new_document(<<~JS)
    () => {
      globalThis.injected = 123;
    }
  JS
  page.goto("#{server.prefix}/empty.html")
  result = page.evaluate("() => globalThis.injected")
  expect(result).to eq(123)

  pending "Page.add_script_tag not implemented"
  page.add_script_tag(content: "window.e = 10;")
  result = page.evaluate("() => globalThis.e")
  expect(result).to be_nil
end

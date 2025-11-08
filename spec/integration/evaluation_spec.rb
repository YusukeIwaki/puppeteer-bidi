# frozen_string_literal: true

RSpec.describe 'Evaluation', type: :integration do
  describe 'Page.evaluate' do
    it 'should work' do
      with_test_state do |page:, **|
        result = page.evaluate(<<~JAVASCRIPT)
          () => {
            return 7 * 3;
          }
        JAVASCRIPT
        expect(result).to eq(21)
      end
    end

    it 'should transfer NaN' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a', Float::NAN)
        expect(result.nan?).to be true
      end
    end

    it 'should transfer -0' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a', -0.0)
        # Ruby doesn't distinguish -0.0 from 0.0 in equality
        # but BiDi should preserve it
        expect(result).to eq(0.0)
        # Check if it's actually -0 by checking 1/result
        expect(1.0 / result).to eq(Float::INFINITY * -1)
      end
    end

    it 'should transfer Infinity' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a', Float::INFINITY)
        expect(result).to eq(Float::INFINITY)
      end
    end

    it 'should transfer -Infinity' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a', -Float::INFINITY)
        expect(result).to eq(-Float::INFINITY)
      end
    end

    it 'should transfer arrays' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a', [1, 2, 3])
        expect(result).to eq([1, 2, 3])
      end
    end

    it 'should modify global environment' do
      with_test_state do |page:, **|
        page.evaluate('() => { return (globalThis.globalVar = 123); }')
        expect(page.evaluate('globalVar')).to eq(123)
      end
    end

    it 'should await promise' do
      with_test_state do |page:, **|
        result = page.evaluate(<<~JAVASCRIPT)
          () => {
            return Promise.resolve(8 * 7);
          }
        JAVASCRIPT
        expect(result).to eq(56)
      end
    end

    it 'should transfer arrays as arrays, not objects' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => Array.isArray(a)', [1, 2, 3])
        expect(result).to be true
      end
    end

    it 'should work with unicode chars' do
      with_test_state do |page:, **|
        result = page.evaluate("(a) => a['中文字符']", { '中文字符' => 42 })
        expect(result).to eq(42)
      end
    end

    it 'should throw when evaluation throws' do
      with_test_state do |page:, **|
        expect {
          page.evaluate('() => { return notExistingObject.property; }')
        }.to raise_error(/notExistingObject/)
      end
    end

    it 'should support thrown strings as error messages' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate("() => { throw 'qwerty'; }")
        rescue => e
          error = e
        end
        expect(error).not_to be_nil
        expect(error.message).to include('qwerty')
      end
    end

    it 'should accept element handle as an argument' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>42</section>')
        element = page.query_selector('section')
        text = page.evaluate('(e) => e.textContent', element)
        expect(text).to eq('42')
      end
    end

    example 'should return proper type for strings' do
      with_test_state do |page:, **|
        result = page.evaluate('() => "hello"')
        expect(result).to be_a(String)
        expect(result).to eq('hello')
      end
    end

    example 'should return proper type for numbers' do
      with_test_state do |page:, **|
        result = page.evaluate('() => 42')
        expect(result).to be_a(Integer)
        expect(result).to eq(42)
      end
    end

    it 'should return proper type for booleans' do
      with_test_state do |page:, **|
        result = page.evaluate('() => true')
        expect(result).to be true
      end
    end

    it 'should return undefined for objects with undefined properties' do
      with_test_state do |page:, **|
        result = page.evaluate('() => ({ a: undefined })')
        expect(result).to eq({ 'a' => nil })
      end
    end

    it 'should properly serialize nested objects' do
      with_test_state do |page:, **|
        result = page.evaluate('() => ({ a: { b: { c: 42 } } })')
        expect(result).to eq({ 'a' => { 'b' => { 'c' => 42 } } })
      end
    end

    it 'should properly serialize null' do
      with_test_state do |page:, **|
        result = page.evaluate('() => null')
        expect(result).to be_nil
      end
    end

    it 'should properly serialize undefined' do
      with_test_state do |page:, **|
        result = page.evaluate('() => undefined')
        expect(result).to be_nil
      end
    end

    it 'should transfer maps' do
      with_test_state do |page:, **|
        result = page.evaluate('() => { const map = new Map(); map.set("key", "value"); return map; }')
        # Maps are serialized as objects in BiDi
        expect(result).to be_a(Hash)
        expect(result['key']).to eq('value')
      end
    end
  end

  describe 'Frame.evaluate' do
    it 'should work via main_frame' do
      with_test_state do |page:, **|
        frame = page.main_frame
        result = frame.evaluate('() => 7 * 3')
        expect(result).to eq(21)
      end
    end

    it 'should transfer values correctly' do
      with_test_state do |page:, **|
        frame = page.main_frame
        result = frame.evaluate('(a, b) => a + b', 3, 4)
        expect(result).to eq(7)
      end
    end
  end
end

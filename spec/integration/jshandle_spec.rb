# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSHandle', type: :integration do
  describe 'Page.evaluateHandle' do
    example 'should work' do
      with_test_state do |page:, server:, **|
        window_handle = page.evaluate_handle('window')
        expect(window_handle).not_to be_nil
        expect(window_handle).to be_a(Puppeteer::Bidi::JSHandle)
      end
    end

    example 'should return the RemoteObject' do
      with_test_state do |page:, server:, **|
        window_handle = page.evaluate_handle('window')
        remote_object = window_handle.remote_object
        expect(remote_object).to be_a(Hash)
        expect(remote_object['type']).not_to be_nil
      end
    end

    example 'should accept object handle as an argument' do
      with_test_state do |page:, server:, **|
        navigator_handle = page.evaluate_handle('() => navigator')
        text = page.evaluate('(e) => e.userAgent', navigator_handle)
        expect(text).to include('Mozilla')
      end
    end

    example 'should accept object handle to primitive types' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle('5')
        is_five = page.evaluate('(e) => Object.is(e, 5)', a_handle)
        expect(is_five).to be true
      end
    end

    example 'should accept object handle to unserializable value' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle('Infinity')
        is_infinity = page.evaluate('(e) => Object.is(e, Infinity)', a_handle)
        expect(is_infinity).to be true
      end
    end
  end

  describe 'JSHandle#get_property' do
    example 'should work' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle("({ one: 1, two: 2, three: 3 })")
        two_handle = a_handle.get_property('two')
        expect(two_handle.json_value).to eq(2)
      end
    end
  end

  describe 'JSHandle#json_value' do
    example 'should work' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle("({ foo: 'bar' })")
        json = a_handle.json_value
        expect(json).to eq({ 'foo' => 'bar' })
      end
    end

    example 'should work with jsonValues that are not objects' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle('[1, 2, 3]')
        json = a_handle.json_value
        expect(json).to eq([1, 2, 3])
      end
    end

    example 'should work with jsonValues that are primitives' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle("'foo'")
        json = a_handle.json_value
        expect(json).to eq('foo')

        b_handle = page.evaluate_handle('undefined')
        json = b_handle.json_value
        expect(json).to be_nil
      end
    end

    example 'should work with dates' do
      with_test_state do |page:, server:, **|
        date_handle = page.evaluate_handle('new Date("2020-05-27T01:31:38.506Z")')
        date = date_handle.json_value
        expect(date).to be_a(Time)
        expect(date.iso8601(3)).to eq('2020-05-27T01:31:38.506Z')
      end
    end

    example 'should not throw for circular objects' do
      with_test_state do |page:, server:, **|
        handle = page.evaluate_handle(<<~JS)
          (() => {
            const obj = { a: 1 };
            obj.self = obj;
            return obj;
          })()
        JS

        expect { handle.json_value }.not_to raise_error
      end
    end
  end

  describe 'JSHandle#get_properties' do
    example 'should work' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle("({ foo: 'bar' })")
        properties = a_handle.get_properties
        expect(properties).to be_a(Hash)
        expect(properties['foo']).not_to be_nil

        foo_value = properties['foo'].json_value
        expect(foo_value).to eq('bar')
      end
    end

    example 'should return even non-own properties' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle(<<~JS)
          (() => {
            class A {
              constructor() {
                this.a = '1';
              }
            }
            class B extends A {
              constructor() {
                super();
                this.b = '2';
              }
            }
            return new B();
          })()
        JS

        properties = a_handle.get_properties
        expect(properties['a'].json_value).to eq('1')
        expect(properties['b'].json_value).to eq('2')
      end
    end
  end

  describe 'JSHandle#as_element' do
    example 'should work' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle('document.body')
        element = a_handle.as_element
        expect(element).not_to be_nil
        expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
      end
    end

    example 'should return null for non-elements' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle('2')
        element = a_handle.as_element
        expect(element).to be_nil
      end
    end

    example 'should return ElementHandle for TextNodes' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>ee!</div>')
        a_handle = page.evaluate_handle('document.querySelector("div").firstChild')
        element = a_handle.as_element
        expect(element).not_to be_nil
        expect(element).to be_a(Puppeteer::Bidi::ElementHandle)

        # Verify it's actually a text node
        is_text_node = page.evaluate('(e) => e.nodeType === Node.TEXT_NODE', element)
        expect(is_text_node).to be true
      end
    end
  end

  describe 'JSHandle#to_s' do
    example 'should work for primitives' do
      with_test_state do |page:, server:, **|
        number_handle = page.evaluate_handle('2')
        expect(number_handle.to_s).to eq('JSHandle:2')

        string_handle = page.evaluate_handle("'a'")
        expect(string_handle.to_s).to eq('JSHandle:a')
      end
    end

    example 'should work for complicated objects' do
      with_test_state do |page:, server:, **|
        a_handle = page.evaluate_handle('window')
        expect(a_handle.to_s).to eq('JSHandle@window')
      end
    end

    example 'should work with different subtypes' do
      with_test_state do |page:, server:, **|
        test_cases = {
          'function' => '(function(){})',
          'array' => '[1, 2, 3]',
          'regexp' => '/foo/',
          'date' => 'new Date()',
          'map' => 'new Map()',
          'set' => 'new Set()',
          'weakmap' => 'new WeakMap()',
          'weakset' => 'new WeakSet()',
          'error' => 'new Error()',
          'typedarray' => 'new Int32Array()',
          'proxy' => 'new Proxy({}, {})'
        }

        test_cases.each do |expected_type, expression|
          handle = page.evaluate_handle(expression)
          expect(handle.to_s).to match(/JSHandle@#{expected_type}/i)
        end
      end
    end
  end

  describe 'JSHandle disposal' do
    example 'should work' do
      with_test_state do |page:, server:, **|
        window_handle = page.evaluate_handle('window')
        expect(window_handle.disposed?).to be false

        window_handle.dispose
        expect(window_handle.disposed?).to be true
      end
    end

    example 'should throw after disposal' do
      with_test_state do |page:, server:, **|
        handle = page.evaluate_handle("({foo: 'bar'})")
        handle.dispose

        expect { handle.get_property('foo') }.to raise_error(/disposed/i)
      end
    end
  end
end

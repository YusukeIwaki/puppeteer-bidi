# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'QuerySelector', type: :integration do
  describe 'Page.query_selector' do
    it 'should query existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>test</section>')
        element = page.query_selector('section')
        expect(element).not_to be_nil
        expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>test</section>')
        element = page.query_selector('non-existing-element')
        expect(element).to be_nil
      end
    end
  end

  describe 'ElementHandle.query_selector' do
    it 'should query existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<div class="second"><div class="inner">A</div></div><div class="third"><div class="inner">B</div></div>')
        html = page.query_selector('html')
        expect(html).not_to be_nil

        second = html.query_selector('.second')
        expect(second).not_to be_nil

        inner = second.query_selector('.inner')
        expect(inner).not_to be_nil

        content = page.evaluate('(e) => e.textContent', inner)
        expect(content).to eq('A')
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>test</div>')
        html = page.query_selector('html')
        element = html.query_selector('.non-existing')
        expect(element).to be_nil
      end
    end
  end

  describe 'Page.query_selector_all' do
    it 'should query existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>A</div><br/><div>B</div>')
        elements = page.query_selector_all('div')
        expect(elements.length).to eq(2)

        # Verify we can evaluate on elements
        results = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(results).to eq(['A', 'B'])
      end
    end

    it 'should return empty array for non-existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<span>A</span>')
        elements = page.query_selector_all('div')
        expect(elements).to eq([])
      end
    end
  end

  describe 'ElementHandle.query_selector_all' do
    it 'should query existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<div><p>A</p><p>B</p></div>')
        div = page.query_selector('div')
        elements = div.query_selector_all('p')
        expect(elements.length).to eq(2)

        results = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(results).to eq(['A', 'B'])
      end
    end

    it 'should return empty array for non-existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<div><span>A</span></div>')
        div = page.query_selector('div')
        elements = div.query_selector_all('p')
        expect(elements).to eq([])
      end
    end
  end
end

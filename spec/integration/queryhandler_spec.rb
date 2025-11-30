# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'QueryHandler', type: :integration do
  describe 'XPath selectors' do
    # Note: XPath support for query_selector/query_selector_all requires
    # implementing QueryHandler integration. Currently only wait_for_selector
    # supports XPath via the QueryHandler system.

    describe 'in Page' do
      it 'should query existing element', skip: 'XPath support for query_selector not implemented (needs QueryHandler integration)' do
        with_test_state do |page:, server:, **|
          page.set_content('<section>test</section>')

          element = page.query_selector('xpath/html/body/section')
          expect(element).not_to be_nil

          elements = page.query_selector_all('xpath/html/body/section')
          expect(elements.length).to eq(1)
        end
      end

      it 'should return empty array for non-existing element', skip: 'XPath support for query_selector not implemented (needs QueryHandler integration)' do
        with_test_state do |page:, server:, **|
          element = page.query_selector('xpath/html/body/non-existing-element')
          expect(element).to be_nil

          elements = page.query_selector_all('xpath/html/body/non-existing-element')
          expect(elements.length).to eq(0)
        end
      end

      it 'should return first element', skip: 'XPath support for query_selector not implemented (needs QueryHandler integration)' do
        with_test_state do |page:, server:, **|
          page.set_content('<div>a</div> <div></div>')

          element = page.query_selector('xpath/html/body/div')
          expect(element).not_to be_nil

          text_matches = element.evaluate('e => e.textContent === "a"')
          expect(text_matches).to be true
        end
      end

      it 'should return multiple elements', skip: 'XPath support for query_selector not implemented (needs QueryHandler integration)' do
        with_test_state do |page:, server:, **|
          page.set_content('<div></div> <div></div>')

          elements = page.query_selector_all('xpath/html/body/div')
          expect(elements.length).to eq(2)
        end
      end
    end

    describe 'in ElementHandles' do
      it 'should query existing element', skip: 'XPath support for query_selector not implemented (needs QueryHandler integration)' do
        with_test_state do |page:, server:, **|
          page.set_content('<div class="a">a<span></span></div>')

          element_handle = page.query_selector('div')
          expect(element_handle).not_to be_nil

          span = element_handle.query_selector('xpath/span')
          expect(span).not_to be_nil

          spans = element_handle.query_selector_all('xpath/span')
          expect(spans.length).to eq(1)
        end
      end

      it 'should return null for non-existing element', skip: 'XPath support for query_selector not implemented (needs QueryHandler integration)' do
        with_test_state do |page:, server:, **|
          page.set_content('<div class="a">a</div>')

          element_handle = page.query_selector('div')
          expect(element_handle).not_to be_nil

          span = element_handle.query_selector('xpath/span')
          expect(span).to be_nil

          spans = element_handle.query_selector_all('xpath/span')
          expect(spans.length).to eq(0)
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Autofill' do
  describe 'ElementHandle.autofill' do
    it 'should fill out a credit card' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/credit-card.html")
        name = page.wait_for_selector('#name')
        name.autofill(
          credit_card: {
            number: '4444444444444444',
            name: 'John Smith',
            expiry_month: '01',
            expiry_year: '2030',
            cvc: '123'
          }
        )
        result = page.evaluate(<<~JS)
          () => {
            const result = [];
            for (const el of document.querySelectorAll('input')) {
              result.push(el.value);
            }
            return result.join(',');
          }
        JS
        expect(result).to eq('John Smith,4444444444444444,01,2030,Submit')
      end
    end
  end
end

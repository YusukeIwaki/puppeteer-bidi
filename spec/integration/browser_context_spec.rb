# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BrowserContext' do
  def permission_state(page, name)
    page.evaluate(<<~JS, name)
      permissionName => {
        return navigator.permissions.query({name: permissionName}).then(result => {
          return result.state;
        });
      }
    JS
  end

  describe 'BrowserContext.new_page' do
    it 'should create a background page' do
      with_test_state do |context:, **|
        page = nil
        begin
          page = context.new_page(background: true)
          expect(page.evaluate('() => document.visibilityState')).to eq('hidden')
        rescue Puppeteer::Bidi::Connection::ProtocolError => error
          pending "Background page creation is not supported by this browser: #{error.message}"
          raise error
        ensure
          page&.close unless page&.closed?
        end
      end
    end
  end

  describe 'BrowserContext.set_permission' do
    it 'should set permission state for an origin' do
      with_test_state do |page:, context:, server:, **|
        page.goto(server.empty_page)

        context.set_permission(server.empty_page, {
          permission: { name: 'geolocation' },
          state: 'granted'
        })
        expect(permission_state(page, 'geolocation')).to eq('granted')

        context.set_permission(server.empty_page, {
          permission: { name: 'geolocation' },
          state: 'denied'
        })
        expect(permission_state(page, 'geolocation')).to eq('denied')

        context.set_permission(server.empty_page, {
          permission: { name: 'geolocation' },
          state: 'prompt'
        })
        expect(permission_state(page, 'geolocation')).to eq('prompt')
      end
    end

    it 'should reject wildcard origin' do
      with_test_state do |context:, **|
        expect {
          context.set_permission('*', {
            permission: { name: 'geolocation' },
            state: 'granted'
          })
        }.to raise_error(Puppeteer::Bidi::UnsupportedOperationError, /Origin \(\*\) is not supported/)
      end
    end
  end

  describe 'BrowserContext.clear_permission_overrides' do
    it 'should reset override_permissions back to prompt' do
      with_test_state do |page:, context:, server:, **|
        page.goto(server.empty_page)
        expect(permission_state(page, 'geolocation')).to eq('prompt')

        context.override_permissions(server.empty_page, ['geolocation'])
        expect(permission_state(page, 'geolocation')).to eq('granted')

        context.clear_permission_overrides
        expect(permission_state(page, 'geolocation')).to eq('prompt')
      end
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Puppeteer::Bidi::CookieUtils do
  describe '.convert_cookies_same_site_bidi_to_cdp' do
    it 'maps unknown values to Default' do
      expect(described_class.convert_cookies_same_site_bidi_to_cdp(nil)).to eq('Default')
      expect(described_class.convert_cookies_same_site_bidi_to_cdp('default')).to eq('Default')
      expect(described_class.convert_cookies_same_site_bidi_to_cdp('unknown')).to eq('Default')
    end
  end

  describe '.convert_cookies_same_site_cdp_to_bidi' do
    it 'maps unknown values to default' do
      expect(described_class.convert_cookies_same_site_cdp_to_bidi(nil)).to eq('default')
      expect(described_class.convert_cookies_same_site_cdp_to_bidi('Default')).to eq('default')
      expect(described_class.convert_cookies_same_site_cdp_to_bidi('Unknown')).to eq('default')
    end
  end
end

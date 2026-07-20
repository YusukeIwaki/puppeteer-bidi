# frozen_string_literal: true

require "spec_helper"

RSpec.describe Puppeteer::Bidi::Core::Realm do
  let(:realm_class) do
    Class.new(described_class) do
      protected

      def session
        nil
      end
    end
  end

  it "emits destroyed before disposing its event listeners" do
    realm = realm_class.new("realm-id", "https://example.com")
    destroyed_events = []
    realm.on(:destroyed) { |event| destroyed_events << event }

    realm.dispose

    expected_reason = "Realm already destroyed, probably because all associated browsing contexts closed."
    expect(destroyed_events).to eq([expected_reason])
    expect(realm).to be_disposed
  end
end

# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # LazyArg defers evaluation of expensive arguments (e.g., handles) until
    # serialization time. Mirrors Puppeteer's LazyArg helper.
    class LazyArg
      def self.create(&block)
        raise ArgumentError, 'LazyArg requires a block' unless block

        new(&block)
      end

      def initialize(&block)
        @block = block
      end

      def resolve
        @block.call
      end
    end
  end
end

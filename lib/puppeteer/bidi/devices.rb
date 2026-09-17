# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Known device descriptors, ported from upstream `KnownDevices`.
    # Covers the current iPhone lineup: iPhone SE (3rd generation), the
    # iPhone 16 family and 16e, and the iPhone 17 family including Air/17e.
    #
    # Each entry has a `:user_agent` string and a `:viewport` hash with
    # `:width`, `:height`, `:device_scale_factor`, `:is_mobile`,
    # `:has_touch`, and `:is_landscape` keys, ready for `Page#emulate`.
    KnownDevices = {
      "iPhone SE (3rd gen)" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) " \
          "AppleWebKit/603.1.30 (KHTML, like Gecko) Version/26.5 Mobile/19E241 Safari/602.1",
        viewport: {
          width: 375,
          height: 667,
          device_scale_factor: 2,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone SE (3rd gen) landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) " \
          "AppleWebKit/603.1.30 (KHTML, like Gecko) Version/26.5 Mobile/19E241 Safari/602.1",
        viewport: {
          width: 667,
          height: 375,
          device_scale_factor: 2,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 16" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 393,
          height: 659,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 16 landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 734,
          height: 343,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 16 Plus" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 430,
          height: 739,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 16 Plus landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 814,
          height: 380,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 16 Pro" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 402,
          height: 681,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 16 Pro landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 756,
          height: 352,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 16 Pro Max" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 440,
          height: 763,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 16 Pro Max landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 838,
          height: 390,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 16e" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 390,
          height: 651,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 16e landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 726,
          height: 340,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 17" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 402,
          height: 681,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 17 landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 756,
          height: 352,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone Air" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 420,
          height: 719,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone Air landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 794,
          height: 370,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 17 Pro" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 402,
          height: 681,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 17 Pro landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 756,
          height: 352,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 17 Pro Max" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 440,
          height: 763,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 17 Pro Max landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 838,
          height: 390,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
      "iPhone 17e" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 390,
          height: 651,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: false,
        },
      },
      "iPhone 17e landscape" => {
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1",
        viewport: {
          width: 726,
          height: 340,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true,
          is_landscape: true,
        },
      },
    }.freeze #: Hash[String, Hash[Symbol, untyped]]
  end
end

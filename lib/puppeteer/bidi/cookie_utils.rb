# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module CookieUtils
      CDP_SPECIFIC_PREFIX = "goog:"

      # @rbs cookie: Hash[untyped, untyped] -- Cookie with symbol or string keys
      # @rbs return: Hash[String, untyped] -- Cookie with string keys
      def self.normalize_cookie_input(cookie)
        cookie.transform_keys(&:to_s)
      end

      # @rbs bidi_cookie: Hash[String, untyped] -- BiDi cookie
      # @rbs return_composite_partition_key: bool -- Whether to return composite partition key
      # @rbs return: Hash[String, untyped] -- Puppeteer cookie
      def self.bidi_to_puppeteer_cookie(bidi_cookie, return_composite_partition_key: false)
        value = bidi_cookie["value"]
        value = value["value"] if value.is_a?(Hash)

        expiry = bidi_cookie["expiry"]
        partition_key = bidi_cookie["#{CDP_SPECIFIC_PREFIX}partitionKey"]

        cookie = {
          "name" => bidi_cookie["name"],
          "value" => value,
          "domain" => bidi_cookie["domain"],
          "path" => bidi_cookie["path"],
          "size" => bidi_cookie["size"],
          "httpOnly" => bidi_cookie["httpOnly"],
          "secure" => bidi_cookie["secure"],
          "sameSite" => convert_cookies_same_site_bidi_to_cdp(bidi_cookie["sameSite"]),
          "expires" => expiry.nil? ? -1 : expiry,
          "session" => expiry.nil? || expiry <= 0,
        }.compact

        cookie.merge!(cdp_specific_cookie_properties_from_bidi(bidi_cookie, "sameParty", "sourceScheme",
                                                              "partitionKeyOpaque", "priority"))
        cookie.merge!(partition_key_from_bidi(partition_key, return_composite_partition_key))

        cookie
      end

      # @rbs same_site: String? -- BiDi SameSite value
      # @rbs return: String -- Puppeteer SameSite
      def self.convert_cookies_same_site_bidi_to_cdp(same_site)
        case same_site
        when "strict"
          "Strict"
        when "lax"
          "Lax"
        else
          "None"
        end
      end

      # @rbs same_site: String? -- Puppeteer SameSite
      # @rbs return: String? -- BiDi SameSite
      def self.convert_cookies_same_site_cdp_to_bidi(same_site)
        case same_site
        when "Strict"
          "strict"
        when "Lax"
          "lax"
        when "None"
          "none"
        else
          nil
        end
      end

      # @rbs expiry: Numeric? -- Cookie expiry
      # @rbs return: Numeric? -- BiDi expiry
      def self.convert_cookies_expiry_cdp_to_bidi(expiry)
        return nil if expiry.nil? || expiry == -1

        expiry
      end

      # @rbs partition_key: String | Hash[String, untyped] | Hash[Symbol, untyped] | nil -- Partition key
      # @rbs return: String? -- BiDi partition key
      def self.convert_cookies_partition_key_from_puppeteer_to_bidi(partition_key)
        return partition_key if partition_key.nil? || partition_key.is_a?(String)

        normalized = normalize_cookie_input(partition_key)
        if normalized["hasCrossSiteAncestor"]
          raise UnsupportedOperationError, "WebDriver BiDi does not support `hasCrossSiteAncestor` yet."
        end

        normalized["sourceOrigin"]
      end

      # @rbs cookie: Hash[String, untyped] -- Cookie data
      # @rbs *property_names: Array[String] -- Cookie property names
      # @rbs return: Hash[String, untyped] -- CDP-specific properties with goog: prefix
      def self.cdp_specific_cookie_properties_from_puppeteer_to_bidi(cookie, *property_names)
        property_names.each_with_object({}) do |property, result|
          next unless cookie.key?(property)

          value = cookie[property]
          next if value.nil?

          result["#{CDP_SPECIFIC_PREFIX}#{property}"] = value
        end
      end

      # @rbs cookie: Hash[String, untyped] -- BiDi cookie data
      # @rbs *property_names: Array[String] -- Cookie property names
      # @rbs return: Hash[String, untyped] -- CDP-specific properties
      def self.cdp_specific_cookie_properties_from_bidi(cookie, *property_names)
        property_names.each_with_object({}) do |property, result|
          key = "#{CDP_SPECIFIC_PREFIX}#{property}"
          next unless cookie.key?(key)

          result[property] = cookie[key]
        end
      end

      # @rbs cookie: Hash[String, untyped] -- Puppeteer cookie
      # @rbs normalized_url: URI::Generic -- URL to match
      # @rbs return: bool -- Whether cookie matches URL
      def self.test_url_match_cookie(cookie, normalized_url)
        return false unless test_url_match_cookie_hostname(cookie, normalized_url)

        test_url_match_cookie_path(cookie, normalized_url)
      end

      # @rbs cookie: Hash[String, untyped] -- Puppeteer cookie
      # @rbs normalized_url: URI::Generic -- URL to match
      # @rbs return: bool -- Whether hostname matches
      def self.test_url_match_cookie_hostname(cookie, normalized_url)
        url_hostname = normalized_url.host
        return false if url_hostname.nil?

        cookie_domain = cookie.fetch("domain", "").downcase
        url_hostname = url_hostname.downcase

        return true if cookie_domain == url_hostname

        cookie_domain.start_with?(".") && url_hostname.end_with?(cookie_domain)
      end

      # @rbs cookie: Hash[String, untyped] -- Puppeteer cookie
      # @rbs normalized_url: URI::Generic -- URL to match
      # @rbs return: bool -- Whether path matches
      def self.test_url_match_cookie_path(cookie, normalized_url)
        uri_path = normalized_url.path
        uri_path = "/" if uri_path.nil? || uri_path.empty?

        cookie_path = cookie["path"] || "/"

        return true if uri_path == cookie_path

        if uri_path.start_with?(cookie_path)
          return true if cookie_path.end_with?("/")
          return true if uri_path[cookie_path.length] == "/"
        end

        false
      end

      # @rbs partition_key: untyped -- BiDi partition key
      # @rbs return_composite_partition_key: bool -- Whether to return composite partition key
      # @rbs return: Hash[String, untyped] -- Partition key info
      def self.partition_key_from_bidi(partition_key, return_composite_partition_key)
        return {} if partition_key.nil?

        if partition_key.is_a?(String)
          return { "partitionKey" => partition_key }
        end

        return {} unless partition_key.is_a?(Hash)

        normalized = normalize_cookie_input(partition_key)
        top_level_site = normalized["topLevelSite"]
        has_cross_site_ancestor = normalized["hasCrossSiteAncestor"]

        if return_composite_partition_key
          return {
            "partitionKey" => {
              "sourceOrigin" => top_level_site,
              "hasCrossSiteAncestor" => has_cross_site_ancestor.nil? ? false : has_cross_site_ancestor,
            },
          }
        end

        { "partitionKey" => top_level_site }
      end
    end
  end
end

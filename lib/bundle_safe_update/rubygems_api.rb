# frozen_string_literal: true

require 'net/http'
require 'json'
require 'time'

module BundleSafeUpdate
  class RubygemsApi
    API_BASE = 'https://rubygems.org/api/v1/versions'

    class ApiError < StandardError; end

    def initialize(http_client: nil)
      @http_client = http_client
    end

    def fetch_version_info(gem_name, version)
      versions = fetch_versions(gem_name)
      versions.find { |v| v['number'] == version }
    end

    def fetch_versions(gem_name)
      uri = URI("#{API_BASE}/#{gem_name}.json")
      response = perform_request(uri)

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError, "Failed to fetch versions for #{gem_name}: #{response.code}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ApiError, "Invalid JSON response for #{gem_name}: #{e.message}"
    end

    def version_age_days(gem_name, version)
      info = fetch_version_info(gem_name, version)
      return nil unless info

      created_at = Time.parse(info['created_at'])
      ((Time.now - created_at) / 86_400).to_i
    end

    private

    def perform_request(uri)
      return @http_client.call(uri) if @http_client

      Net::HTTP.get_response(uri)
    end
  end
end

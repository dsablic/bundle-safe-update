# frozen_string_literal: true

require 'net/http'
require 'json'
require 'time'

module BundleSafeUpdate
  class RubygemsApi
    VERSIONS_API_BASE = 'https://rubygems.org/api/v1/versions'
    OWNERS_API_BASE = 'https://rubygems.org/api/v1/gems'
    GEM_API_BASE = 'https://rubygems.org/api/v1/gems'
    SECONDS_PER_DAY = 86_400
    HTTP_OPEN_TIMEOUT = 10
    HTTP_READ_TIMEOUT = 30

    class ApiError < StandardError; end

    GemInfo = Struct.new(:downloads, :version_created_at, keyword_init: true)

    def initialize(http_client: nil)
      @http_client = http_client
    end

    def fetch_version_info(gem_name, version)
      versions = fetch_versions(gem_name)
      versions.find { |v| v['number'] == version }
    end

    def fetch_versions(gem_name)
      uri = URI("#{VERSIONS_API_BASE}/#{gem_name}.json")
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
      ((Time.now - created_at) / SECONDS_PER_DAY).to_i
    end

    def fetch_owners(gem_name)
      uri = URI("#{OWNERS_API_BASE}/#{gem_name}/owners.json")
      response = perform_request(uri)

      return [] unless response.is_a?(Net::HTTPSuccess)

      JSON
        .parse(response.body)
        .filter_map { |owner| owner['handle'] }
    rescue JSON::ParserError
      []
    end

    def fetch_gem_info(gem_name)
      uri = URI("#{GEM_API_BASE}/#{gem_name}.json")
      response = perform_request(uri)

      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      GemInfo.new(
        downloads: data['downloads'],
        version_created_at: parse_time(data['version_created_at'])
      )
    rescue JSON::ParserError
      nil
    end

    private

    def parse_time(time_string)
      return nil unless time_string

      Time.parse(time_string)
    rescue ArgumentError
      nil
    end

    def perform_request(uri)
      return @http_client.call(uri) if @http_client

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = HTTP_OPEN_TIMEOUT
      http.read_timeout = HTTP_READ_TIMEOUT
      http.get(uri.request_uri)
    end
  end
end

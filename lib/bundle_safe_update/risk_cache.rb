# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require 'time'

module BundleSafeUpdate
  class RiskCache
    CACHE_FILENAME = 'bundle-safe-update-cache.yml'
    CACHE_VERSION = 1

    OwnerChange = Struct.new(:gem_name, :previous_owners, :current_owners, keyword_init: true)

    def initialize(cache_path: nil)
      @cache_path = cache_path || default_cache_path
      @data = load_cache
    end

    def owners_for(gem_name)
      @data['owners'][gem_name] || []
    end

    def owner_changed?(gem_name, current_owners)
      cached = owners_for(gem_name)
      return false if cached.empty?

      cached.sort != current_owners.compact.sort
    end

    def detect_owner_change(gem_name, current_owners)
      cached = owners_for(gem_name)
      sanitized = current_owners.compact
      return nil if cached.empty? || cached.sort == sanitized.sort

      OwnerChange.new(
        gem_name: gem_name,
        previous_owners: cached,
        current_owners: sanitized
      )
    end

    def update_owners(gem_name, owners)
      @data['owners'][gem_name] = owners.compact.sort
    end

    def save
      @data['updated_at'] = Time.now.iso8601
      File.write(@cache_path, YAML.dump(@data))
    end

    def exists?
      File.exist?(@cache_path)
    end

    private

    def load_cache
      return default_cache unless File.exist?(@cache_path)

      loaded = YAML.safe_load_file(@cache_path) || {}
      return default_cache unless loaded['version'] == CACHE_VERSION

      loaded
    rescue Psych::SyntaxError
      default_cache
    end

    def default_cache
      {
        'version' => CACHE_VERSION,
        'updated_at' => nil,
        'owners' => {}
      }
    end

    def default_cache_path
      bundle_dir = File.join(Dir.pwd, '.bundle')
      FileUtils.mkdir_p(bundle_dir)
      File.join(bundle_dir, CACHE_FILENAME)
    end
  end
end

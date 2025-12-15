# frozen_string_literal: true

require 'time'

module BundleSafeUpdate
  class RiskChecker
    RiskResult = Struct.new(:gem_name, :version, :signals, :blocked, keyword_init: true)
    RiskSignal = Struct.new(:type, :message, :mode, keyword_init: true)

    SECONDS_PER_YEAR = 365.25 * 24 * 60 * 60

    def initialize(config:, api: nil, cache: nil, lockfile_parser: nil, max_threads: nil)
      @config = config
      @api = api || RubygemsApi.new
      @cache = cache || RiskCache.new
      @lockfile_parser = lockfile_parser || LockfileParser.new
      @max_threads = max_threads || @config.max_threads
    end

    def check_all(gem_results)
      return [] if gem_results.empty?

      check_all_parallel(gem_results)
    end

    def save_cache
      @cache.save
    end

    private

    def check_all_parallel(gem_results)
      results = Array.new(gem_results.size)
      queue = Queue.new
      gem_results.each_with_index { |result, idx| queue << [result, idx] }

      threads = spawn_worker_threads(queue, results)
      threads.each(&:join)

      results.compact
    end

    def spawn_worker_threads(queue, results)
      thread_count = [@max_threads, queue.size].min
      Array.new(thread_count) do
        Thread.new { process_queue(queue, results) }
      end
    end

    def process_queue(queue, results)
      loop do
        gem_result, idx = queue.pop(true)
        results[idx] = check_gem(gem_result)
      rescue ThreadError
        break
      end
    end

    def check_gem(gem_result)
      signals = []
      signals.concat(check_low_downloads(gem_result))
      signals.concat(check_stale_gem(gem_result))
      signals.concat(check_new_owner(gem_result))
      signals.concat(check_version_jump(gem_result))

      return nil if signals.empty?

      blocked = signals.any? { |s| s.mode == 'block' }
      RiskResult.new(gem_name: gem_result.name, version: gem_result.version, signals: signals, blocked: blocked)
    end

    def check_low_downloads(gem_result)
      return [] unless @config.risk_signal_enabled?(:low_downloads)
      return [] unless from_rubygems?(gem_result.name)

      gem_info = @api.fetch_gem_info(gem_result.name)
      return [] unless gem_info

      threshold = @config.risk_signal_threshold(:low_downloads, :threshold)
      return [] if gem_info.downloads >= threshold

      [build_signal(:low_downloads, "low downloads (#{gem_info.downloads} total)")]
    end

    def check_stale_gem(gem_result)
      return [] unless @config.risk_signal_enabled?(:stale_gem)
      return [] unless from_rubygems?(gem_result.name)

      gem_info = @api.fetch_gem_info(gem_result.name)
      return [] unless gem_info&.version_created_at

      age_years = calculate_age_years(gem_info.version_created_at)
      threshold_years = @config.risk_signal_threshold(:stale_gem, :threshold_years)
      return [] if age_years < threshold_years

      [build_signal(:stale_gem, "stale gem (last release #{age_years.round(1)} years ago)")]
    end

    def check_new_owner(gem_result)
      return [] unless @config.risk_signal_enabled?(:new_owner)
      return [] unless from_rubygems?(gem_result.name)

      current_owners = @api.fetch_owners(gem_result.name)
      return [] if current_owners.empty?

      change = @cache.detect_owner_change(gem_result.name, current_owners)
      @cache.update_owners(gem_result.name, current_owners)
      return [] unless change

      [build_signal(:new_owner, owner_change_message(change))]
    end

    def from_rubygems?(gem_name)
      source = @lockfile_parser.source_for(gem_name)
      source.nil? || source.include?('rubygems.org')
    end

    def check_version_jump(gem_result)
      return [] unless @config.risk_signal_enabled?(:version_jump)
      return [] unless major_version_jump?(gem_result)

      [build_signal(:version_jump, "major version jump (was #{gem_result.current_version})")]
    end

    def build_signal(type, message)
      RiskSignal.new(type: type, message: message, mode: @config.risk_signal_mode(type))
    end

    def calculate_age_years(timestamp)
      (Time.now - timestamp) / SECONDS_PER_YEAR
    end

    def owner_change_message(change)
      new_owners = change.current_owners.join(', ')
      old_owners = change.previous_owners.join(', ')
      "ownership changed (new: #{new_owners}, was: #{old_owners})"
    end

    def major_version_jump?(gem_result)
      return false unless gem_result.respond_to?(:current_version) && gem_result.current_version

      current = parse_version(gem_result.current_version)
      newest = parse_version(gem_result.version)
      current && newest && newest[:major] > current[:major]
    end

    def parse_version(version_string)
      parts = version_string.to_s.split('.')
      return nil if parts.empty?

      { major: parts[0].to_i, minor: parts[1].to_i, patch: parts[2].to_i }
    end
  end
end

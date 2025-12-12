# frozen_string_literal: true

module BundleSafeUpdate
  class GemChecker
    CheckResult = Struct.new(:name, :version, :age_days, :allowed, :reason, keyword_init: true)

    DEFAULT_MAX_THREADS = 8

    def initialize(config:, api: nil, lockfile_parser: nil, max_threads: nil)
      @config = config
      @api = api || RubygemsApi.new
      @lockfile_parser = lockfile_parser || LockfileParser.new
      @max_threads = max_threads || DEFAULT_MAX_THREADS
    end

    def check_gem(gem_info)
      return ignored_result(gem_info) if @config.ignored?(gem_info.name)
      return trusted_source_result(gem_info) if trusted_source?(gem_info.name)
      return trusted_owner_result(gem_info) if trusted_owner?(gem_info.name)

      age_days = @api.version_age_days(gem_info.name, gem_info.newest_version)
      return not_found_result(gem_info) if age_days.nil?

      age_check_result(gem_info, age_days)
    end

    def check_all(outdated_gems)
      return [] if outdated_gems.empty?

      check_all_parallel(outdated_gems)
    end

    private

    def check_all_parallel(outdated_gems)
      results = Array.new(outdated_gems.size)
      queue = Queue.new
      outdated_gems.each_with_index { |gem_info, idx| queue << [gem_info, idx] }

      threads = spawn_worker_threads(queue, results)
      threads.each(&:join)

      results
    end

    def spawn_worker_threads(queue, results)
      thread_count = [@max_threads, queue.size].min
      Array.new(thread_count) do
        Thread.new do
          process_queue(queue, results)
        end
      end
    end

    def process_queue(queue, results)
      loop do
        gem_info, idx = queue.pop(true)
        results[idx] = check_gem(gem_info)
      rescue ThreadError
        break
      end
    end

    def trusted_source?(gem_name)
      source_url = @lockfile_parser.source_for(gem_name)
      @config.trusted_source?(source_url)
    end

    def trusted_owner?(gem_name)
      return false if @config.trusted_owners.empty?

      owners = @api.fetch_owners(gem_name)
      @config.trusted_owners.intersect?(owners)
    end

    def ignored_result(gem_info)
      build_result(gem_info, age_days: nil, allowed: true, reason: 'ignored')
    end

    def trusted_source_result(gem_info)
      build_result(gem_info, age_days: nil, allowed: true, reason: 'trusted source')
    end

    def trusted_owner_result(gem_info)
      build_result(gem_info, age_days: nil, allowed: true, reason: 'trusted owner')
    end

    def not_found_result(gem_info)
      build_result(gem_info, age_days: nil, allowed: false, reason: 'version not found')
    end

    def age_check_result(gem_info, age_days)
      allowed = age_days >= @config.cooldown_days
      reason = allowed ? 'satisfies minimum age' : 'too new'
      build_result(gem_info, age_days: age_days, allowed: allowed, reason: reason)
    end

    def build_result(gem_info, age_days:, allowed:, reason:)
      CheckResult.new(
        name: gem_info.name,
        version: gem_info.newest_version,
        age_days: age_days,
        allowed: allowed,
        reason: reason
      )
    end
  end
end

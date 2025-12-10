# frozen_string_literal: true

module BundleSafeUpdate
  class GemChecker
    CheckResult = Struct.new(:name, :version, :age_days, :allowed, :reason, keyword_init: true)

    def initialize(config:, api: nil, lockfile_parser: nil)
      @config = config
      @api = api || RubygemsApi.new
      @lockfile_parser = lockfile_parser || LockfileParser.new
    end

    def check_gem(gem_info)
      return ignored_result(gem_info) if @config.ignored?(gem_info.name)
      return trusted_source_result(gem_info) if trusted_source?(gem_info.name)

      age_days = @api.version_age_days(gem_info.name, gem_info.newest_version)
      return not_found_result(gem_info) if age_days.nil?

      age_check_result(gem_info, age_days)
    end

    def check_all(outdated_gems)
      outdated_gems.map { |gem_info| check_gem(gem_info) }
    end

    private

    def trusted_source?(gem_name)
      source_url = @lockfile_parser.source_for(gem_name)
      @config.trusted_source?(source_url)
    end

    def ignored_result(gem_info)
      build_result(gem_info, age_days: nil, allowed: true, reason: 'ignored')
    end

    def trusted_source_result(gem_info)
      build_result(gem_info, age_days: nil, allowed: true, reason: 'trusted source')
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

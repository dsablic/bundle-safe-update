# frozen_string_literal: true

require 'bundler'
require 'optparse'
require 'json'
require_relative 'cli/options'
require_relative 'cli/output'

module BundleSafeUpdate
  class CLI
    include ColorOutput
    include Options
    include Output

    EXIT_SUCCESS = 0
    EXIT_VIOLATIONS = 1
    EXIT_ERROR = 2

    def self.run(args)
      new.run(args)
    end

    def run(args)
      options, gems = parse_options(args)
      config = Config.new(options)
      return dry_run(config) if options[:dry_run]

      results = check_gems(config, options[:verbose], gems)
      process_results(results, config, options)
    rescue StandardError => e
      handle_error(e, options[:verbose])
      EXIT_ERROR
    end

    private

    def parse_options(args)
      options = {}
      build_option_parser(options).parse!(args)
      [options, args]
    end

    def dry_run(config)
      dry_run_output(config)
      EXIT_SUCCESS
    end

    def check_gems(config, verbose, gems = [])
      puts(cyan('Checking gem versions...')) if verbose
      outdated_gems = OutdatedChecker
                      .new(gems:)
                      .outdated_gems
      return log_empty_result(verbose) if outdated_gems.empty?

      puts(cyan("Found #{outdated_gems.length} outdated gem(s)")) if verbose
      GemChecker
        .new(config:, max_threads: config.max_threads)
        .check_all(outdated_gems)
    end

    def log_empty_result(verbose)
      puts(green('No outdated gems found.')) if verbose
      []
    end

    def process_results(results, config, options)
      allowed, blocked = partition_results(results)
      output_results(results, blocked, config, options)
      risk_results = run_risk_check(results, config, options)
      perform_update(allowed, blocked, risk_results, config) if config.update && allowed.any?
      determine_exit_code(config, blocked, risk_results, run_audit(config, options))
    end

    def run_risk_check(results, config, options)
      return [] if options[:risk] == false

      risk_checker = RiskChecker.new(config: config)
      risk_results = options[:refresh_cache] ? [] : risk_checker.check_all(results)
      output_risk_results(risk_results, options) unless options[:json]
      risk_checker.save_cache
      risk_results
    end

    def partition_results(results)
      [results.select(&:allowed), results.reject(&:allowed)]
    end

    def output_results(results, blocked, config, options)
      options[:json] ? output_json(results, blocked, config) : output_human(results, blocked, config)
    end

    def determine_exit_code(config, blocked, risk_results, audit_result)
      return EXIT_SUCCESS if config.warn_only
      return EXIT_SUCCESS unless violations?(blocked, risk_results, audit_result)

      EXIT_VIOLATIONS
    end

    def violations?(blocked, risk_results, audit_result)
      blocked.any? || risk_results.any?(&:blocked) || audit_result&.vulnerabilities&.any?
    end

    def run_audit(config, options)
      return nil unless config.audit

      audit_result = AuditChecker.new.check
      output_audit_result(audit_result) unless options[:json]
      audit_result
    end

    def perform_update(allowed, blocked, risk_results, config)
      risk_blocked_names = risk_results.select(&:blocked).map(&:gem_name)
      updatable = allowed.reject { |r| risk_blocked_names.include?(r.name) }
      return if updatable.empty?

      gem_names = updatable.map(&:name)
      command = update_command(gem_names, config.lock_only)
      print_update_start(gem_names, config.lock_only)
      result = Bundler.with_unbundled_env do
        system(*command)
      end
      print_update_result(result)
      print_skipped(blocked, risk_blocked_names)
    end

    def update_command(gem_names, lock_only)
      if lock_only
        ['bundle', 'lock', '--update', *gem_names]
      else
        ['bundle', 'update', *gem_names]
      end
    end

    def handle_error(error, verbose)
      warn(red("Error: #{error.message}"))
      warn(error.backtrace.join("\n")) if verbose
    end
  end
end

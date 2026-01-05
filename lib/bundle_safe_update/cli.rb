# frozen_string_literal: true

require 'bundler'
require 'optparse'
require 'json'
require_relative 'cli/output'

module BundleSafeUpdate
  class CLI
    include ColorOutput
    include Output

    EXIT_SUCCESS = 0
    EXIT_VIOLATIONS = 1
    EXIT_ERROR = 2

    def self.run(args)
      new.run(args)
    end

    def run(args)
      options = parse_options(args)
      config = Config.new(options)
      return dry_run(config) if options[:dry_run]

      results = check_gems(config, options[:verbose])
      process_results(results, config, options)
    rescue StandardError => e
      handle_error(e, options[:verbose])
      EXIT_ERROR
    end

    private

    def parse_options(args)
      options = {}
      build_option_parser(options).parse!(args)
      options
    end

    def build_option_parser(options)
      OptionParser.new do |opts|
        opts.banner = 'Usage: bundle-safe-update [options]'
        define_config_options(opts, options)
        define_output_options(opts, options)
        define_info_options(opts)
      end
    end

    def define_config_options(opts, options)
      opts.on('--config PATH', 'Path to config file') { |path| options[:config] = path }
      opts.on('--cooldown DAYS', Integer, 'Minimum age in days') { |days| options[:cooldown] = days }
      opts.on('--update', 'Update gems that pass the cooldown check') { options[:update] = true }
      opts.on('--no-audit', 'Skip vulnerability audit') { options[:audit] = false }
      opts.on('--no-risk', 'Skip risk signal checking') { options[:risk] = false }
      opts.on('--refresh-cache', 'Refresh owner cache without warnings') { options[:refresh_cache] = true }
      opts.on('--dry-run', 'Show configuration without checking') { options[:dry_run] = true }
    end

    def define_output_options(opts, options)
      opts.on('--json', 'Output in JSON format') { options[:json] = true }
      opts.on('--verbose', 'Enable verbose output') { options[:verbose] = true }
    end

    def define_info_options(opts)
      opts.on('-v', '--version', 'Show version') do
        puts("bundle-safe-update #{VERSION}")
        exit(EXIT_SUCCESS)
      end
      opts.on('-h', '--help', 'Show this help') do
        puts(opts)
        exit(EXIT_SUCCESS)
      end
    end

    def dry_run(config)
      dry_run_output(config)
      EXIT_SUCCESS
    end

    def check_gems(config, verbose)
      puts(cyan('Checking gem versions...')) if verbose
      outdated_gems = OutdatedChecker
                      .new
                      .outdated_gems
      return log_empty_result(verbose) if outdated_gems.empty?

      puts(cyan("Found #{outdated_gems.length} outdated gem(s)")) if verbose
      GemChecker
        .new(config: config, max_threads: config.max_threads)
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
      perform_update(allowed, blocked, risk_results) if config.update && allowed.any?
      determine_exit_code(blocked, risk_results, run_audit(config, options))
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

    def determine_exit_code(blocked, risk_results, audit_result)
      has_risk_blocks = risk_results.any?(&:blocked)
      has_violations = blocked.any? || has_risk_blocks || audit_result&.vulnerabilities&.any?
      has_violations ? EXIT_VIOLATIONS : EXIT_SUCCESS
    end

    def run_audit(config, options)
      return nil unless config.audit

      audit_result = AuditChecker.new.check
      output_audit_result(audit_result) unless options[:json]
      audit_result
    end

    def perform_update(allowed, blocked, risk_results)
      risk_blocked_names = risk_results.select(&:blocked).map(&:gem_name)
      updatable = allowed.reject { |r| risk_blocked_names.include?(r.name) }
      return if updatable.empty?

      gem_names = updatable.map(&:name)
      print_update_start(gem_names)
      result = Bundler.with_unbundled_env do
        system('bundle', 'update', *gem_names)
      end
      print_update_result(result)
      print_skipped(blocked, risk_blocked_names)
    end

    def handle_error(error, verbose)
      warn(red("Error: #{error.message}"))
      warn(error.backtrace.join("\n")) if verbose
    end
  end
end

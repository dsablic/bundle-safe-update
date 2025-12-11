# frozen_string_literal: true

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
        .new(config: config)
        .check_all(outdated_gems)
    end

    def log_empty_result(verbose)
      puts(green('No outdated gems found.')) if verbose
      []
    end

    def process_results(results, config, options)
      allowed = results.select(&:allowed)
      blocked = results.reject(&:allowed)

      options[:json] ? output_json(results, blocked, config) : output_human(results, blocked, config)
      perform_update(allowed, blocked) if config.update && allowed.any?

      blocked.empty? ? EXIT_SUCCESS : EXIT_VIOLATIONS
    end

    def perform_update(allowed, blocked)
      gem_names = allowed.map(&:name)
      print_update_start(gem_names)
      run_bundle_update(gem_names)
      print_skipped(blocked) if blocked.any?
    end

    def print_update_start(gem_names)
      puts
      puts(cyan("Updating #{gem_names.length} gem(s): #{gem_names.join(', ')}"))
      puts(cyan("Running: bundle update #{gem_names.join(' ')}"))
    end

    def run_bundle_update(gem_names)
      success = system('bundle', 'update', *gem_names)
      puts(success ? green('Bundle updated successfully.') : red('Bundle update failed.'))
    end

    def print_skipped(blocked)
      names = blocked.map(&:name).join(', ')
      puts
      puts(yellow("Skipped #{blocked.length} blocked gem(s): #{names}"))
    end

    def handle_error(error, verbose)
      warn(red("Error: #{error.message}"))
      warn(error.backtrace.join("\n")) if verbose
    end
  end
end

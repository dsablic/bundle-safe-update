# frozen_string_literal: true

require 'optparse'
require 'json'

module BundleSafeUpdate
  class CLI
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
      output_results(results, config, options)
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
      puts('Configuration (dry-run):')
      puts("  Cooldown days: #{config.cooldown_days}")
      puts("  Ignored gems: #{format_list(config.ignore_gems)}")
      puts("  Ignored prefixes: #{format_list(config.ignore_prefixes)}")
      puts("  Trusted sources: #{format_list(config.trusted_sources)}")
      puts("  Verbose: #{config.verbose}")
      EXIT_SUCCESS
    end

    def format_list(items)
      items.empty? ? '(none)' : items.join(', ')
    end

    def check_gems(config, verbose)
      puts('Checking gem versions...') if verbose
      outdated_gems = OutdatedChecker
                      .new
                      .outdated_gems
      return log_empty_result(verbose) if outdated_gems.empty?

      puts("Found #{outdated_gems.length} outdated gem(s)") if verbose
      GemChecker
        .new(config: config)
        .check_all(outdated_gems)
    end

    def log_empty_result(verbose)
      puts('No outdated gems found.') if verbose
      []
    end

    def output_results(results, config, options)
      blocked = results.reject(&:allowed)
      options[:json] ? output_json(results, blocked, config) : output_human(results, blocked, config)
      blocked.empty? ? EXIT_SUCCESS : EXIT_VIOLATIONS
    end

    def output_json(results, blocked, config)
      puts(JSON.pretty_generate(build_json_output(results, blocked, config)))
    end

    def build_json_output(results, blocked, config)
      {
        ok: blocked.empty?,
        cooldown_days: config.cooldown_days,
        checked: results.length,
        blocked: blocked.map { |r| { name: r.name, version: r.version, age_days: r.age_days } }
      }
    end

    def output_human(results, blocked, config)
      results.each { |result| print_result(result, config) }
      print_summary(blocked)
    end

    def print_result(result, config)
      if result.allowed
        puts("OK: #{result.name} (#{result.version}) - #{result.reason}")
      else
        puts("BLOCKED: #{result.name} (#{result.version}) - #{blocked_reason(result, config)}")
      end
    end

    def blocked_reason(result, config)
      age_info = result.age_days ? "published #{result.age_days} days ago" : result.reason
      "#{age_info} (< #{config.cooldown_days} required)"
    end

    def print_summary(blocked)
      puts
      message =
        if blocked.empty?
          'All gem versions satisfy minimum age requirements.'
        else
          "#{blocked.length} gem(s) violate minimum release age"
        end
      puts(message)
    end

    def handle_error(error, verbose)
      warn("Error: #{error.message}")
      warn(error.backtrace.join("\n")) if verbose
    end
  end
end

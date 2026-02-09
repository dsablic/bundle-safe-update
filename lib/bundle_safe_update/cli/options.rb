# frozen_string_literal: true

module BundleSafeUpdate
  class CLI
    module Options
      def build_option_parser(options)
        OptionParser.new do |opts|
          opts.banner = 'Usage: bundle-safe-update [options] [gem1 gem2 ...]'
          define_config_options(opts, options)
          define_output_options(opts, options)
          define_info_options(opts)
        end
      end

      def define_config_options(opts, options)
        define_basic_config_options(opts, options)
        define_skip_options(opts, options)
      end

      def define_basic_config_options(opts, options)
        opts.on('--config PATH', 'Path to config file') { |path| options[:config] = path }
        opts.on('--cooldown DAYS', Integer, 'Minimum age in days') { |days| options[:cooldown] = days }
        opts.on('--update', 'Update gems that pass the cooldown check') { options[:update] = true }
        opts.on('--lock-only', 'Update Gemfile.lock without installing gems') { options[:lock_only] = true }
        opts.on('--warn-only', 'Report violations but exit with success') { options[:warn_only] = true }
        opts.on('--dry-run', 'Show configuration without checking') { options[:dry_run] = true }
      end

      def define_skip_options(opts, options)
        opts.on('--no-audit', 'Skip vulnerability audit') { options[:audit] = false }
        opts.on('--no-risk', 'Skip risk signal checking') { options[:risk] = false }
        opts.on('--refresh-cache', 'Refresh owner cache without warnings') { options[:refresh_cache] = true }
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
    end
  end
end

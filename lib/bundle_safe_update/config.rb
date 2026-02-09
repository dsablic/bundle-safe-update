# frozen_string_literal: true

require 'yaml'

module BundleSafeUpdate
  class Config
    DEFAULT_COOLDOWN_DAYS = 14
    CONFIG_FILENAME = '.bundle-safe-update.yml'

    DEFAULT_MAX_THREADS = 32

    DEFAULT_RISK_SIGNALS = {
      'low_downloads' => { 'mode' => 'warn', 'threshold' => 1000 },
      'stale_gem' => { 'mode' => 'warn', 'threshold_years' => 3 },
      'new_owner' => { 'mode' => 'warn', 'threshold_days' => 90 },
      'version_jump' => { 'mode' => 'warn' }
    }.freeze

    DEFAULTS = {
      'cooldown_days' => DEFAULT_COOLDOWN_DAYS,
      'ignore_prefixes' => [],
      'ignore_gems' => [],
      'trusted_sources' => [],
      'trusted_owners' => [],
      'max_threads' => DEFAULT_MAX_THREADS,
      'audit' => true,
      'verbose' => false,
      'update' => false,
      'lock_only' => false,
      'warn_only' => false,
      'risk_signals' => DEFAULT_RISK_SIGNALS
    }.freeze

    attr_reader :cooldown_days, :ignore_prefixes, :ignore_gems, :trusted_sources, :trusted_owners,
                :max_threads, :audit, :verbose, :update, :lock_only, :warn_only, :risk_signals

    def initialize(options = {})
      config = merge_configs(options)
      assign_basic_options(config)
      assign_risk_options(config)
    end

    def risk_signal_mode(signal_name)
      @risk_signals.dig(signal_name.to_s, 'mode') || 'off'
    end

    def risk_signal_enabled?(signal_name)
      risk_signal_mode(signal_name) != 'off'
    end

    def risk_signal_threshold(signal_name, key)
      @risk_signals.dig(signal_name.to_s, key.to_s)
    end

    def ignored?(gem_name)
      return true if @ignore_gems.include?(gem_name)

      @ignore_prefixes.any? { |prefix| gem_name.start_with?(prefix) }
    end

    def trusted_source?(source_url)
      return false if source_url.nil? || @trusted_sources.empty?

      @trusted_sources.any? { |pattern| source_url.include?(pattern) }
    end

    private

    def assign_basic_options(config)
      @cooldown_days = config['cooldown_days']
      @ignore_prefixes = config['ignore_prefixes']
      @ignore_gems = config['ignore_gems']
      @trusted_sources = config['trusted_sources']
      @trusted_owners = config['trusted_owners']
      @max_threads = config['max_threads']
    end

    def assign_risk_options(config)
      @audit = config['audit']
      @verbose = config['verbose']
      @update = config['update']
      @lock_only = config['lock_only']
      @warn_only = config['warn_only']
      @risk_signals = config['risk_signals']
    end

    def merge_configs(cli_options)
      config = DEFAULTS.dup
      config = deep_merge(config, load_global_config)
      config = deep_merge(config, load_local_config)
      config = deep_merge(config, load_custom_config(cli_options[:config]))
      apply_cli_overrides(config, cli_options)
    end

    def load_global_config
      global_path = File.join(Dir.home, CONFIG_FILENAME)
      load_config_file(global_path)
    end

    def load_local_config
      local_path = File.join(Dir.pwd, CONFIG_FILENAME)
      load_config_file(local_path)
    end

    def load_custom_config(path)
      return {} unless path

      load_config_file(path)
    end

    def load_config_file(path)
      return {} unless File.exist?(path)

      YAML.safe_load_file(path) || {}
    rescue Psych::SyntaxError => e
      warn("Warning: Invalid YAML in #{path}: #{e.message}")
      {}
    end

    def apply_cli_overrides(config, options)
      config['cooldown_days'] = options[:cooldown] if options[:cooldown]
      apply_boolean_overrides(config, options)
      config
    end

    def apply_boolean_overrides(config, options)
      %i[audit verbose update lock_only warn_only].each do |key|
        config[key.to_s] = options[key] if options.key?(key)
      end
    end

    def deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end

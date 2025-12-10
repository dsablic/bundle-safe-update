# frozen_string_literal: true

module BundleSafeUpdate
  class LockfileParser
    LOCKFILE_NAME = 'Gemfile.lock'
    GEM_SECTION_START = /^GEM$/
    SECTION_HEADER = /^[A-Z]+$/
    REMOTE_LINE = /^\s+remote:\s+(.+)$/
    GEM_LINE = /^\s{4}(\S+)\s+\(/

    def initialize(lockfile_path: nil)
      @lockfile_path = lockfile_path || File.join(Dir.pwd, LOCKFILE_NAME)
    end

    def gem_sources
      return @gem_sources if defined?(@gem_sources)

      @gem_sources = parse_lockfile
    end

    def source_for(gem_name)
      gem_sources[gem_name]
    end

    private

    def parse_lockfile
      return {} unless File.exist?(@lockfile_path)

      content = File.read(@lockfile_path)
      extract_gem_sources(content)
    rescue StandardError => e
      warn("Warning: Could not parse #{@lockfile_path}: #{e.message}")
      {}
    end

    def extract_gem_sources(content)
      sources = {}
      state = { in_gem_section: false, current_remote: nil }

      content.each_line do |line|
        process_line(line, state, sources)
      end

      sources
    end

    def process_line(line, state, sources)
      case line
      when GEM_SECTION_START then state[:in_gem_section] = true
      when SECTION_HEADER then reset_section(state)
      when REMOTE_LINE then update_remote(state, ::Regexp.last_match(1))
      when GEM_LINE then add_gem_source(sources, state, ::Regexp.last_match(1))
      end
    end

    def reset_section(state)
      state[:in_gem_section] = false
      state[:current_remote] = nil
    end

    def update_remote(state, remote)
      state[:current_remote] = remote.strip if state[:in_gem_section]
    end

    def add_gem_source(sources, state, gem_name)
      return unless state[:in_gem_section] && state[:current_remote]

      sources[gem_name] = state[:current_remote]
    end
  end
end

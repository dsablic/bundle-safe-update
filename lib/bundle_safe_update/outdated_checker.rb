# frozen_string_literal: true

require 'bundler'
require 'open3'

module BundleSafeUpdate
  class OutdatedChecker
    OutdatedGem = Struct.new(:name, :current_version, :newest_version, keyword_init: true)

    BUNDLE_COMMAND = %w[bundle outdated --parseable].freeze

    def initialize(gems: [], executor: nil)
      @gems = gems
      @executor = executor || method(:execute_command)
    end

    def outdated_gems
      command = BUNDLE_COMMAND + @gems
      output = @executor.call(command)
      parse_output(output)
    end

    private

    def execute_command(command)
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(*command)
      end
      check_for_errors(stderr, status)
      stdout
    end

    def check_for_errors(stderr, status)
      return if status.success? || status.exitstatus == 1

      raise stderr.strip if stderr.include?('Your Ruby version is')

      raise "bundle outdated failed with exit code #{status.exitstatus}: #{stderr.strip}"
    end

    def parse_output(output)
      output
        .lines
        .map(&:strip)
        .select { |line| line.include?('(newest') }
        .map { |line| parse_line(line) }
        .compact
    end

    def parse_line(line)
      match = line.match(/^(\S+)\s+\(newest\s+([\d.]+),?\s*installed\s+([\d.]+)/)
      return nil unless match

      OutdatedGem.new(
        name: match[1],
        newest_version: match[2],
        current_version: match[3]
      )
    end
  end
end

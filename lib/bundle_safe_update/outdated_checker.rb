# frozen_string_literal: true

require 'open3'

module BundleSafeUpdate
  class OutdatedChecker
    OutdatedGem = Struct.new(:name, :current_version, :newest_version, keyword_init: true)

    BUNDLE_COMMAND = %w[bundle outdated --parseable].freeze

    def initialize(executor: nil)
      @executor = executor || method(:execute_command)
    end

    def outdated_gems
      output = @executor.call(BUNDLE_COMMAND)
      parse_output(output)
    end

    private

    def execute_command(command)
      stdout, _stderr, _status = Open3.capture3(*command)
      stdout
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

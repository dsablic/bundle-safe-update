# frozen_string_literal: true

module BundleSafeUpdate
  class OutdatedChecker
    OutdatedGem = Struct.new(:name, :current_version, :newest_version, keyword_init: true)

    class BundlerError < StandardError; end

    def initialize(executor: nil)
      @executor = executor || method(:execute_command)
    end

    def outdated_gems
      output = @executor.call('bundle outdated --parseable')
      parse_output(output)
    end

    private

    def execute_command(command)
      `#{command} 2>&1`
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

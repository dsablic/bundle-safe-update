# frozen_string_literal: true

require 'open3'

module BundleSafeUpdate
  class AuditChecker
    AuditResult = Struct.new(:available, :vulnerabilities, :error, keyword_init: true)
    Vulnerability = Struct.new(:gem_name, :cve, :title, :solution, keyword_init: true)

    AUDIT_COMMAND = %w[bundle audit check --update].freeze

    def initialize(executor: nil)
      @executor = executor || method(:execute_command)
    end

    def check
      return unavailable_result unless audit_available?

      stdout, stderr, status = @executor.call(AUDIT_COMMAND)
      parse_result(stdout, stderr, status)
    end

    def audit_available?
      _stdout, _stderr, status = Open3.capture3('bundle', 'audit', '--version')
      status.success?
    rescue Errno::ENOENT
      false
    end

    private

    def execute_command(command)
      Open3.capture3(*command)
    end

    def unavailable_result
      AuditResult.new(available: false, vulnerabilities: [], error: nil)
    end

    def parse_result(stdout, stderr, status)
      if status.success?
        AuditResult.new(available: true, vulnerabilities: [], error: nil)
      elsif stdout.include?('Vulnerabilities found!')
        AuditResult.new(available: true, vulnerabilities: parse_vulnerabilities(stdout), error: nil)
      else
        AuditResult.new(available: true, vulnerabilities: [], error: stderr.strip)
      end
    end

    def parse_vulnerabilities(output)
      vulnerabilities = []
      current = {}

      output.each_line do |line|
        current, completed = parse_vulnerability_line(line, current)
        vulnerabilities << completed if completed
      end

      vulnerabilities
    end

    def parse_vulnerability_line(line, current)
      key, value = extract_field(line)
      return [current, nil] unless key

      current[key] = value
      return [{}, Vulnerability.new(**current)] if key == :solution

      [current, nil]
    end

    def extract_field(line)
      case line
      when /^Name:\s+(.+)$/ then [:gem_name, ::Regexp.last_match(1).strip]
      when /^CVE:\s+(.+)$/ then [:cve, ::Regexp.last_match(1).strip]
      when /^Title:\s+(.+)$/ then [:title, ::Regexp.last_match(1).strip]
      when /^Solution:\s+(.+)$/ then [:solution, ::Regexp.last_match(1).strip]
      end
    end
  end
end

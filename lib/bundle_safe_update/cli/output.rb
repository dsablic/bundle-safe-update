# frozen_string_literal: true

module BundleSafeUpdate
  class CLI
    module Output
      def dry_run_output(config)
        puts('Configuration (dry-run):')
        config_lines(config).each { |line| puts(line) }
      end

      def config_lines(config)
        config_values(config).map { |label, value| "  #{label}: #{value}" }
      end

      def config_values(config)
        { 'Cooldown days' => config.cooldown_days, 'Ignored gems' => format_list(config.ignore_gems),
          'Ignored prefixes' => format_list(config.ignore_prefixes),
          'Trusted sources' => format_list(config.trusted_sources),
          'Trusted owners' => format_list(config.trusted_owners), 'Max threads' => config.max_threads,
          'Audit' => config.audit, 'Update' => config.update, 'Verbose' => config.verbose }
      end

      def format_list(items)
        items.empty? ? '(none)' : items.join(', ')
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
          puts(green("OK: #{result.name} (#{result.version}) - #{result.reason}"))
        else
          puts(yellow("BLOCKED: #{result.name} (#{result.version}) - #{blocked_reason(result, config)}"))
        end
      end

      def blocked_reason(result, config)
        age_info = result.age_days ? "published #{result.age_days} days ago" : result.reason
        "#{age_info} (< #{config.cooldown_days} required)"
      end

      def print_summary(blocked)
        puts
        if blocked.empty?
          puts(green('All gem versions satisfy minimum age requirements.'))
        else
          puts(yellow("#{blocked.length} gem(s) violate minimum release age"))
        end
      end

      def output_audit_result(result)
        return print_audit_unavailable unless result.available
        return print_audit_error(result.error) if result.error

        print_audit_results(result.vulnerabilities)
      end

      def print_audit_unavailable
        warn(yellow('Warning: bundler-audit not installed. Run: gem install bundler-audit'))
      end

      def print_audit_error(error)
        warn(red("Audit error: #{error}"))
      end

      def print_audit_results(vulnerabilities)
        puts
        puts(cyan('Checking for vulnerabilities...'))

        if vulnerabilities.empty?
          puts(green('No vulnerabilities found.'))
        else
          vulnerabilities.each { |v| print_vulnerability(v) }
          puts
          puts(yellow("#{vulnerabilities.length} vulnerability(ies) found"))
        end
      end

      def print_vulnerability(vuln)
        puts(red("VULNERABLE: #{vuln.gem_name} (#{vuln.cve}) - #{vuln.title}"))
        puts("  Solution: #{vuln.solution}") if vuln.solution
      end
    end
  end
end

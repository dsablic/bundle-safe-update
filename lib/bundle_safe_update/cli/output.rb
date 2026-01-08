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
          'Audit' => config.audit, 'Update' => config.update, 'Warn only' => config.warn_only,
          'Verbose' => config.verbose }
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

      def output_risk_results(risk_results, options)
        return if risk_results.empty? || options[:json]

        puts
        puts(cyan('Risk signals:'))
        risk_results.each { |result| print_risk_result(result) }
        print_risk_summary(risk_results)
      end

      def print_risk_result(result)
        result.signals.each { |signal| print_risk_signal(result, signal) }
      end

      def print_risk_signal(result, signal)
        prefix = signal.mode == 'block' ? red('BLOCKED') : yellow('WARNING')
        puts("#{prefix}: #{result.gem_name} (#{result.version}) - #{signal.message}")
      end

      def print_risk_summary(risk_results)
        warnings = risk_results.sum { |r| r.signals.count { |s| s.mode == 'warn' } }
        blocks = risk_results.count(&:blocked)

        puts
        puts(yellow("#{blocks} gem(s) blocked by risk signals")) if blocks.positive?
        puts(yellow("#{warnings} risk warning(s)")) if warnings.positive?
      end

      def print_update_start(gem_names)
        puts
        puts(cyan("Updating #{gem_names.length} gem(s): #{gem_names.join(', ')}"))
        puts(cyan("Running: bundle update #{gem_names.join(' ')}"))
      end

      def print_update_result(success)
        puts(success ? green('Bundle updated successfully.') : red('Bundle update failed.'))
      end

      def print_skipped(blocked, risk_blocked_names)
        total_skipped = blocked.length + risk_blocked_names.length
        return if total_skipped.zero?

        cooldown_names = blocked.map(&:name)
        all_skipped = (cooldown_names + risk_blocked_names).uniq.join(', ')
        puts
        puts(yellow("Skipped #{total_skipped} blocked gem(s): #{all_skipped}"))
      end
    end
  end
end

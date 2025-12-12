# bundle-safe-update

A CLI tool that enforces a minimum release age for Ruby gems during updates, preventing installation of gem versions that are "too new" (e.g., less than 14 days old). This helps protect against supply chain attacks by ensuring gems have had time for community review.

## Installation

```sh
gem install bundle-safe-update
```

Or add to your Gemfile:

```ruby
gem 'bundle-safe-update', group: :development
```

## Usage

Run in your project directory:

```sh
bundle-safe-update
```

### CLI Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to config file |
| `--cooldown DAYS` | Minimum age in days (overrides config) |
| `--update` | Update gems that pass the cooldown check |
| `--no-audit` | Skip vulnerability audit |
| `--no-risk` | Skip risk signal checking |
| `--refresh-cache` | Refresh owner cache without warnings |
| `--json` | Output in JSON format for CI systems |
| `--verbose` | Enable verbose output |
| `--dry-run` | Show configuration without checking |
| `-v, --version` | Show version |
| `-h, --help` | Show help |

### Example Output

Human-readable output:

```
Checking gem versions...
OK: rails (7.1.3.2) - satisfies minimum age (42 days)
BLOCKED: nokogiri (1.16.4) - published 3 days ago (< 14 required)

1 gem(s) violate minimum release age
```

JSON output (`--json`):

```json
{
  "ok": false,
  "cooldown_days": 14,
  "checked": 2,
  "blocked": [
    { "name": "nokogiri", "version": "1.16.4", "age_days": 3 }
  ]
}
```

### Updating Safe Gems

By default, `bundle-safe-update` only checks gems and reports results. Use `--update` to automatically update gems that pass the cooldown check:

```sh
bundle-safe-update --update
```

Example output:

```
OK: rails (7.1.3.2) - satisfies minimum age
BLOCKED: nokogiri (1.16.4) - published 3 days ago (< 14 required)

1 gem(s) violate minimum release age

Updating 1 gem(s): rails
Running: bundle update rails
Bundle updated successfully.

Skipped 1 blocked gem(s): nokogiri
```

This allows you to safely update gems while respecting the cooldown period for newly released versions.

### Vulnerability Auditing

By default, bundle-safe-update runs `bundle audit` to check for known security vulnerabilities. This requires the `bundler-audit` gem to be installed:

```sh
gem install bundler-audit
```

If `bundler-audit` is not installed, a warning is displayed but the check continues. The audit database is automatically updated before each check.

Example output with vulnerabilities:

```
OK: rails (7.1.3.2) - satisfies minimum age

Checking for vulnerabilities...
VULNERABLE: actionpack (CVE-2024-1234) - Possible XSS vulnerability
  Solution: upgrade to >= 7.0.8.1

1 vulnerability(ies) found
```

To skip the audit check, use `--no-audit` or set `audit: false` in config.

### Risk Intelligence

Bundle-safe-update analyzes gems for risk signals that may indicate supply chain threats:

| Signal | Description | Default Threshold |
|--------|-------------|-------------------|
| Low downloads | Gems with very few total downloads | < 1,000 |
| Stale gem | Gems not updated recently | > 3 years |
| New owner | Gems with recent ownership changes | Ownership changed since last run |
| Version jump | Major version bumps | Any major bump |

Example output with risk warnings:

```
OK: rails (7.1.3.2) - satisfies minimum age

Risk signals:
WARNING: tiny-lib (2.0.0) - low downloads (847 total)
WARNING: old-parser (1.5.0) - stale gem (last release 4.2 years ago)
BLOCKED: some-gem (5.0.0) - major version jump (was 2.3.1)

1 gem(s) blocked by risk signals
2 risk warning(s)
```

Each signal can be set to `warn` (default), `block`, or `off`:

```yaml
risk_signals:
  low_downloads:
    mode: warn           # off | warn | block
    threshold: 1000      # minimum total downloads

  stale_gem:
    mode: warn
    threshold_years: 3   # years since last release

  new_owner:
    mode: block          # block on ownership changes
    threshold_days: 90   # (reserved for future use)

  version_jump:
    mode: warn
```

Owner changes are detected by caching gem owners locally (`.bundle/bundle-safe-update-cache.yml`). On first run, no warnings are generated - owners are just cached. Subsequent runs detect changes.

Use `--refresh-cache` to rebuild the cache without triggering warnings (useful after intentional ownership changes). Use `--no-risk` to skip risk checking entirely.

## Configuration

Create `.bundle-safe-update.yml` in your project root or home directory:

```yaml
# Minimum age in days for gem versions (default: 14)
cooldown_days: 14

# Gems to ignore completely (e.g., internal gems)
ignore_gems:
  - rails
  - sidekiq

# Prefixes to ignore (e.g., company gems)
ignore_prefixes:
  - mycompany-
  - internal-

# Trust gems from specific sources (skip cooldown check)
# Useful for private gem servers where gems are already vetted
trusted_sources:
  - ruby.cloudsmith.io
  - gems.mycompany.com

# Trust gems by RubyGems owner/publisher (skip cooldown check)
# Useful for well-known publishers like AWS, Google, etc.
trusted_owners:
  - awscloud  # AWS SDK gems

# Automatically update gems that pass the cooldown check (default: false)
update: false

# Run vulnerability audit with bundler-audit (default: true)
audit: true

# Enable verbose output
verbose: false
```

### Trusted Sources

Gems from trusted sources skip the cooldown check entirely. The source is determined by parsing `Gemfile.lock`. This is useful for:

- Private gem servers (Cloudsmith, Gemfury, self-hosted)
- Internal gems that are already vetted by your organization

Example output for trusted gems:
```
OK: mycompany-auth (1.2.0) - trusted source
```

### Trusted Owners

Gems owned by trusted RubyGems users skip the cooldown check. The owner is fetched from the RubyGems API. This is useful for:

- Well-known publishers (AWS, Google, Rails core team, etc.)
- Organizations with strong security practices

Example output for trusted owner gems:
```
OK: aws-sdk-s3 (1.180.0) - trusted owner
```

To find a gem's owner, visit `https://rubygems.org/gems/{gem_name}` and look at the "Owners" section, or use:
```sh
curl https://rubygems.org/api/v1/gems/{gem_name}/owners.json
```

### Config Resolution Order

1. CLI flags (highest priority)
2. Project `.bundle-safe-update.yml`
3. Home directory `~/.bundle-safe-update.yml`
4. Built-in defaults

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Blocked by cooldown, risk signals, or vulnerabilities |
| 2 | Unexpected error |

## CI Integration

### Bitbucket Pipelines

```yaml
pipelines:
  default:
    - step:
        name: Check gem versions
        script:
          - gem install bundle-safe-update
          - bundle-safe-update --json
```

### AWS CodeBuild

```yaml
version: 0.2
phases:
  install:
    commands:
      - gem install bundle-safe-update
  build:
    commands:
      - bundle-safe-update --json
```

### GitHub Actions

```yaml
- name: Check gem versions
  run: |
    gem install bundle-safe-update
    bundle-safe-update --json
```

## Development

```sh
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop
```

## License

MIT License. See [LICENSE.txt](LICENSE.txt).

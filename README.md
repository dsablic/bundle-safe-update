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

# Enable verbose output
verbose: false
```

### Config Resolution Order

1. CLI flags (highest priority)
2. Project `.bundle-safe-update.yml`
3. Home directory `~/.bundle-safe-update.yml`
4. Built-in defaults

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All gem versions satisfy minimum age |
| 1 | One or more gems are too new |
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

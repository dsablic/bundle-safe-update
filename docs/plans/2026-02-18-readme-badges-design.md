# README Badges Design

**Date:** 2026-02-18

## Summary

Add three standard badges to the README.md for the `bundle-safe-update` gem.

## Badges

Insert immediately after the `# bundle-safe-update` heading, before the description paragraph:

```markdown
[![CI](https://github.com/dsablic/bundle-safe-update/actions/workflows/ci.yml/badge.svg)](https://github.com/dsablic/bundle-safe-update/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/bundle-safe-update.svg)](https://badge.fury.io/rb/bundle-safe-update)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
```

- **CI**: GitHub Actions status for the `CI` workflow on `master`
- **Gem Version**: Current published version from RubyGems via badge.fury.io
- **License**: Static MIT badge via shields.io

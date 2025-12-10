# frozen_string_literal: true

require_relative 'lib/bundle_safe_update/version'

Gem::Specification.new do |spec|
  spec.name = 'bundle-safe-update'
  spec.version = BundleSafeUpdate::VERSION
  spec.authors = ['Denis Sablic']
  spec.email = ['denis@readcube.com']

  spec.summary = 'Enforce minimum release age for Ruby gems during updates'
  spec.description = 'A CLI tool that prevents installation of gem versions ' \
                     'that are too new (e.g., <14 days old), helping protect ' \
                     'against supply chain attacks.'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?('spec/', '.git', '.rspec', '.rubocop', 'TODO.md')
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['bundle-safe-update']
  spec.require_paths = ['lib']
end

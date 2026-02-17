# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::LockfileParser do
  let(:lockfile_content) do
    <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          rails (7.1.3)
          nokogiri (1.16.4)

      GEM
        remote: https://gems.example.com/private/
        specs:
          mycompany-auth (1.2.0)
          mycompany-utils (0.5.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rails
        mycompany-auth
    LOCKFILE
  end

  let(:lockfile_path) { '/tmp/test-Gemfile.lock' }
  let(:parser) { described_class.new(lockfile_path: lockfile_path) }

  before do
    allow(File).to receive(:exist?).with(lockfile_path).and_return(true)
    allow(File).to receive(:read).with(lockfile_path).and_return(lockfile_content)
  end

  describe '#gem_sources' do
    it 'returns a hash mapping gems to their sources' do
      sources = parser.gem_sources
      expect(sources).to be_a(Hash)
      expect(sources.keys).to contain_exactly('rails', 'nokogiri', 'mycompany-auth', 'mycompany-utils')
    end

    it 'maps rubygems.org gems correctly' do
      sources = parser.gem_sources
      expect(sources['rails']).to eq('https://rubygems.org/')
      expect(sources['nokogiri']).to eq('https://rubygems.org/')
    end

    it 'maps private source gems correctly' do
      sources = parser.gem_sources
      expect(sources['mycompany-auth']).to eq('https://gems.example.com/private/')
      expect(sources['mycompany-utils']).to eq('https://gems.example.com/private/')
    end
  end

  describe '#source_for' do
    it 'returns the source URL for a gem' do
      expect(parser.source_for('rails')).to eq('https://rubygems.org/')
      expect(parser.source_for('mycompany-auth')).to eq('https://gems.example.com/private/')
    end

    it 'returns nil for unknown gems' do
      expect(parser.source_for('unknown-gem')).to be_nil
    end
  end

  describe 'when lockfile does not exist' do
    before do
      allow(File).to receive(:exist?).with(lockfile_path).and_return(false)
    end

    it 'returns empty hash for gem_sources' do
      expect(parser.gem_sources).to eq({})
    end

    it 'returns nil for source_for' do
      expect(parser.source_for('rails')).to be_nil
    end
  end

  describe 'when lockfile is malformed' do
    before do
      allow(File).to receive(:read).with(lockfile_path).and_raise(StandardError, 'read error')
    end

    it 'returns empty hash and warns' do
      expect { parser.gem_sources }.to output(/Warning/).to_stderr
      expect(parser.gem_sources).to eq({})
    end
  end
end

# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::GemChecker do
  let(:config) do
    instance_double(
      BundleSafeUpdate::Config,
      cooldown_days: 14,
      ignore_gems: [],
      ignore_prefixes: [],
      trusted_sources: [],
      trusted_owners: []
    )
  end

  let(:api) { instance_double(BundleSafeUpdate::RubygemsApi) }
  let(:lockfile_parser) { instance_double(BundleSafeUpdate::LockfileParser) }
  let(:checker) { described_class.new(config: config, api: api, lockfile_parser: lockfile_parser) }

  let(:gem_info) do
    BundleSafeUpdate::OutdatedChecker::OutdatedGem.new(
      name: 'nokogiri',
      current_version: '1.16.2',
      newest_version: '1.16.4'
    )
  end

  before do
    allow(lockfile_parser).to receive(:source_for).and_return('https://rubygems.org/')
    allow(config).to receive(:trusted_source?).and_return(false)
  end

  describe '#check_gem' do
    context 'when gem is old enough' do
      before do
        allow(config).to receive(:ignored?).with('nokogiri').and_return(false)
        allow(api).to receive(:version_age_days).with('nokogiri', '1.16.4').and_return(20)
      end

      it 'returns allowed result' do
        result = checker.check_gem(gem_info)
        expect(result.allowed).to be(true)
        expect(result.age_days).to eq(20)
        expect(result.reason).to eq('satisfies minimum age')
      end
    end

    context 'when gem is too new' do
      before do
        allow(config).to receive(:ignored?).with('nokogiri').and_return(false)
        allow(api).to receive(:version_age_days).with('nokogiri', '1.16.4').and_return(3)
      end

      it 'returns blocked result' do
        result = checker.check_gem(gem_info)
        expect(result.allowed).to be(false)
        expect(result.age_days).to eq(3)
        expect(result.reason).to eq('too new')
      end
    end

    context 'when gem is ignored' do
      before do
        allow(config).to receive(:ignored?).with('nokogiri').and_return(true)
      end

      it 'returns allowed result without API call' do
        expect(api).not_to receive(:version_age_days)

        result = checker.check_gem(gem_info)
        expect(result.allowed).to be(true)
        expect(result.reason).to eq('ignored')
      end
    end

    context 'when gem is from trusted source' do
      before do
        allow(config).to receive(:ignored?).with('nokogiri').and_return(false)
        allow(lockfile_parser).to receive(:source_for)
          .with('nokogiri')
          .and_return('https://ruby.cloudsmith.io/readcube/main/')
        allow(config).to receive(:trusted_source?)
          .with('https://ruby.cloudsmith.io/readcube/main/')
          .and_return(true)
      end

      it 'returns allowed result without API call' do
        expect(api).not_to receive(:version_age_days)

        result = checker.check_gem(gem_info)
        expect(result.allowed).to be(true)
        expect(result.reason).to eq('trusted source')
      end
    end

    context 'when gem is from trusted owner' do
      let(:config) do
        instance_double(
          BundleSafeUpdate::Config,
          cooldown_days: 14,
          ignore_gems: [],
          ignore_prefixes: [],
          trusted_sources: [],
          trusted_owners: %w[alexrothenberg]
        )
      end

      before do
        allow(config).to receive(:ignored?).with('nokogiri').and_return(false)
        allow(config).to receive(:trusted_source?).and_return(false)
        allow(api).to receive(:fetch_owners).with('nokogiri').and_return(%w[alexrothenberg flavorjones])
      end

      it 'returns allowed result without age check' do
        expect(api).not_to receive(:version_age_days)

        result = checker.check_gem(gem_info)
        expect(result.allowed).to be(true)
        expect(result.reason).to eq('trusted owner')
      end
    end

    context 'when version not found' do
      before do
        allow(config).to receive(:ignored?).with('nokogiri').and_return(false)
        allow(api).to receive(:version_age_days).with('nokogiri', '1.16.4').and_return(nil)
      end

      it 'returns blocked result' do
        result = checker.check_gem(gem_info)
        expect(result.allowed).to be(false)
        expect(result.reason).to eq('version not found')
      end
    end
  end

  describe '#check_all' do
    let(:gem_info2) do
      BundleSafeUpdate::OutdatedChecker::OutdatedGem.new(
        name: 'rails',
        current_version: '7.0.8',
        newest_version: '7.1.3.2'
      )
    end

    before do
      allow(config).to receive(:ignored?).with('nokogiri').and_return(false)
      allow(config).to receive(:ignored?).with('rails').and_return(true)
      allow(api).to receive(:version_age_days).with('nokogiri', '1.16.4').and_return(3)
    end

    it 'checks all gems' do
      results = checker.check_all([gem_info, gem_info2])
      expect(results.length).to eq(2)

      nokogiri_result = results.find { |r| r.name == 'nokogiri' }
      expect(nokogiri_result.allowed).to be(false)

      rails_result = results.find { |r| r.name == 'rails' }
      expect(rails_result.allowed).to be(true)
    end

    it 'preserves order when processing in parallel' do
      results = checker.check_all([gem_info, gem_info2])
      expect(results[0].name).to eq('nokogiri')
      expect(results[1].name).to eq('rails')
    end

    it 'returns empty array for empty input' do
      results = checker.check_all([])
      expect(results).to eq([])
    end
  end
end

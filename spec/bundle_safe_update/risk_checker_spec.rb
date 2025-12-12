# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::RiskChecker do
  let(:config) { BundleSafeUpdate::Config.new }
  let(:api) { instance_double(BundleSafeUpdate::RubygemsApi) }
  let(:cache) { instance_double(BundleSafeUpdate::RiskCache) }
  let(:checker) { described_class.new(config: config, api: api, cache: cache, max_threads: 1) }

  let(:gem_result) do
    BundleSafeUpdate::GemChecker::CheckResult.new(
      name: 'rails',
      version: '7.1.3.2',
      current_version: '7.0.8',
      age_days: 42,
      allowed: true,
      reason: 'satisfies minimum age'
    )
  end

  before do
    allow(cache).to receive(:detect_owner_change).and_return(nil)
    allow(cache).to receive(:update_owners)
    allow(cache).to receive(:save)
    allow(api).to receive(:fetch_owners).and_return([])
    allow(api).to receive(:fetch_gem_info).and_return(nil)
  end

  describe '#check_all' do
    context 'with empty results' do
      it 'returns empty array' do
        expect(checker.check_all([])).to eq([])
      end
    end

    context 'with no risk signals triggered' do
      before do
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 1_000_000, version_created_at: Time.now)
        )
      end

      it 'returns empty array' do
        expect(checker.check_all([gem_result])).to eq([])
      end
    end
  end

  describe 'low downloads signal' do
    context 'when downloads below threshold' do
      before do
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 500, version_created_at: Time.now)
        )
      end

      it 'triggers low_downloads signal' do
        results = checker.check_all([gem_result])

        expect(results.length).to eq(1)
        expect(results.first.signals.first.type).to eq(:low_downloads)
        expect(results.first.signals.first.message).to include('500 total')
      end
    end

    context 'when downloads above threshold' do
      before do
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 2000, version_created_at: Time.now)
        )
      end

      it 'does not trigger signal' do
        expect(checker.check_all([gem_result])).to eq([])
      end
    end
  end

  describe 'stale gem signal' do
    context 'when gem is stale' do
      before do
        four_years_ago = Time.now - (4 * 365.25 * 24 * 60 * 60)
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 1_000_000, version_created_at: four_years_ago)
        )
      end

      it 'triggers stale_gem signal' do
        results = checker.check_all([gem_result])

        expect(results.length).to eq(1)
        expect(results.first.signals.first.type).to eq(:stale_gem)
        expect(results.first.signals.first.message).to include('years ago')
      end
    end

    context 'when gem is recent' do
      before do
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 1_000_000, version_created_at: Time.now)
        )
      end

      it 'does not trigger signal' do
        expect(checker.check_all([gem_result])).to eq([])
      end
    end
  end

  describe 'new owner signal' do
    before do
      allow(api).to receive(:fetch_gem_info).and_return(
        BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 1_000_000, version_created_at: Time.now)
      )
    end

    context 'when ownership changed' do
      before do
        allow(api).to receive(:fetch_owners).and_return(%w[dhh hacker])
        allow(cache).to receive(:detect_owner_change).and_return(
          BundleSafeUpdate::RiskCache::OwnerChange.new(
            gem_name: 'rails',
            previous_owners: %w[dhh rafaelfranca],
            current_owners: %w[dhh hacker]
          )
        )
      end

      it 'triggers new_owner signal' do
        results = checker.check_all([gem_result])

        expect(results.length).to eq(1)
        expect(results.first.signals.first.type).to eq(:new_owner)
        expect(results.first.signals.first.message).to include('ownership changed')
      end
    end

    context 'when no ownership change' do
      before do
        allow(api).to receive(:fetch_owners).and_return(['dhh'])
        allow(cache).to receive(:detect_owner_change).and_return(nil)
      end

      it 'does not trigger signal' do
        expect(checker.check_all([gem_result])).to eq([])
      end
    end
  end

  describe 'version jump signal' do
    let(:major_jump_result) do
      BundleSafeUpdate::GemChecker::CheckResult.new(
        name: 'rails',
        version: '8.0.0',
        current_version: '7.1.3.2',
        age_days: 42,
        allowed: true,
        reason: 'satisfies minimum age'
      )
    end

    before do
      allow(api).to receive(:fetch_gem_info).and_return(
        BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 1_000_000, version_created_at: Time.now)
      )
    end

    context 'when major version jumped' do
      it 'triggers version_jump signal' do
        results = checker.check_all([major_jump_result])

        expect(results.length).to eq(1)
        expect(results.first.signals.first.type).to eq(:version_jump)
        expect(results.first.signals.first.message).to include('major version jump')
      end
    end

    context 'when minor version change' do
      it 'does not trigger signal' do
        expect(checker.check_all([gem_result])).to eq([])
      end
    end
  end

  describe 'signal modes' do
    context 'when signal mode is block' do
      let(:config) do
        BundleSafeUpdate::Config.new.tap do |c|
          c.instance_variable_set(
            :@risk_signals,
            'low_downloads' => { 'mode' => 'block', 'threshold' => 1000 },
            'stale_gem' => { 'mode' => 'off', 'threshold_years' => 3 },
            'new_owner' => { 'mode' => 'off', 'threshold_days' => 90 },
            'version_jump' => { 'mode' => 'off' }
          )
        end
      end

      before do
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 500, version_created_at: Time.now)
        )
      end

      it 'sets blocked to true' do
        results = checker.check_all([gem_result])

        expect(results.first.blocked).to be(true)
        expect(results.first.signals.first.mode).to eq('block')
      end
    end

    context 'when signal mode is off' do
      let(:config) do
        BundleSafeUpdate::Config.new.tap do |c|
          c.instance_variable_set(
            :@risk_signals,
            'low_downloads' => { 'mode' => 'off', 'threshold' => 1000 },
            'stale_gem' => { 'mode' => 'off', 'threshold_years' => 3 },
            'new_owner' => { 'mode' => 'off', 'threshold_days' => 90 },
            'version_jump' => { 'mode' => 'off' }
          )
        end
      end

      before do
        allow(api).to receive(:fetch_gem_info).and_return(
          BundleSafeUpdate::RubygemsApi::GemInfo.new(downloads: 500, version_created_at: Time.now)
        )
      end

      it 'does not trigger any signals' do
        expect(checker.check_all([gem_result])).to eq([])
      end
    end
  end
end

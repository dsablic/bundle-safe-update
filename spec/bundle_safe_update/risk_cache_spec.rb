# frozen_string_literal: true

require 'tempfile'

RSpec.describe BundleSafeUpdate::RiskCache do
  let(:cache_path) { Tempfile.new('.bundle-safe-update-cache.yml').path }
  let(:cache) { described_class.new(cache_path: cache_path) }

  after { FileUtils.rm_f(cache_path) }

  describe '#owners_for' do
    context 'when gem not in cache' do
      it 'returns empty array' do
        expect(cache.owners_for('rails')).to eq([])
      end
    end

    context 'when gem in cache' do
      before do
        cache.update_owners('rails', %w[dhh rafaelfranca])
        cache.save
      end

      it 'returns cached owners' do
        new_cache = described_class.new(cache_path: cache_path)
        expect(new_cache.owners_for('rails')).to eq(%w[dhh rafaelfranca])
      end
    end
  end

  describe '#owner_changed?' do
    context 'when gem not in cache' do
      it 'returns false' do
        expect(cache.owner_changed?('rails', ['dhh'])).to be(false)
      end
    end

    context 'when owners match' do
      before { cache.update_owners('rails', %w[dhh rafaelfranca]) }

      it 'returns false' do
        expect(cache.owner_changed?('rails', %w[rafaelfranca dhh])).to be(false)
      end
    end

    context 'when owners differ' do
      before { cache.update_owners('rails', %w[dhh rafaelfranca]) }

      it 'returns true' do
        expect(cache.owner_changed?('rails', %w[dhh hacker])).to be(true)
      end
    end
  end

  describe '#detect_owner_change' do
    context 'when no change' do
      before { cache.update_owners('rails', ['dhh']) }

      it 'returns nil' do
        expect(cache.detect_owner_change('rails', ['dhh'])).to be_nil
      end
    end

    context 'when owners changed' do
      before { cache.update_owners('rails', %w[dhh rafaelfranca]) }

      it 'returns OwnerChange struct' do
        change = cache.detect_owner_change('rails', %w[dhh hacker])

        expect(change).to be_a(described_class::OwnerChange)
        expect(change.gem_name).to eq('rails')
        expect(change.previous_owners).to eq(%w[dhh rafaelfranca])
        expect(change.current_owners).to eq(%w[dhh hacker])
      end
    end
  end

  describe '#save and reload' do
    it 'persists owners to disk' do
      cache.update_owners('rails', ['dhh'])
      cache.update_owners('nokogiri', ['flavorjones'])
      cache.save

      new_cache = described_class.new(cache_path: cache_path)
      expect(new_cache.owners_for('rails')).to eq(['dhh'])
      expect(new_cache.owners_for('nokogiri')).to eq(['flavorjones'])
    end
  end

  describe '#exists?' do
    context 'when cache file does not exist' do
      it 'returns false' do
        FileUtils.rm_f(cache_path)
        expect(cache.exists?).to be(false)
      end
    end

    context 'when cache file exists' do
      before { cache.save }

      it 'returns true' do
        expect(cache.exists?).to be(true)
      end
    end
  end
end

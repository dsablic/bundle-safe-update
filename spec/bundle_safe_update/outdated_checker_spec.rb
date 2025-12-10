# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::OutdatedChecker do
  describe '#outdated_gems' do
    let(:parseable_output) do
      <<~OUTPUT
        nokogiri (newest 1.16.4, installed 1.16.2)
        rails (newest 7.1.3.2, installed 7.0.8)
        puma (newest 6.4.2, installed 6.4.0)
      OUTPUT
    end

    let(:executor) { ->(_cmd) { parseable_output } }
    let(:checker) { described_class.new(executor: executor) }

    it 'parses bundle outdated output' do
      gems = checker.outdated_gems
      expect(gems.length).to eq(3)
    end

    it 'extracts gem name' do
      gems = checker.outdated_gems
      expect(gems.map(&:name)).to contain_exactly('nokogiri', 'rails', 'puma')
    end

    it 'extracts newest version' do
      gems = checker.outdated_gems
      nokogiri = gems.find { |g| g.name == 'nokogiri' }
      expect(nokogiri.newest_version).to eq('1.16.4')
    end

    it 'extracts current version' do
      gems = checker.outdated_gems
      nokogiri = gems.find { |g| g.name == 'nokogiri' }
      expect(nokogiri.current_version).to eq('1.16.2')
    end

    context 'with empty output' do
      let(:executor) { ->(_cmd) { '' } }

      it 'returns empty array' do
        gems = checker.outdated_gems
        expect(gems).to eq([])
      end
    end

    context 'with requested version format' do
      let(:parseable_output) do
        <<~OUTPUT
          nokogiri (newest 1.16.4, installed 1.16.2, requested ~> 1.16)
        OUTPUT
      end

      it 'parses gems with requested version' do
        gems = checker.outdated_gems
        expect(gems.length).to eq(1)
        expect(gems.first.name).to eq('nokogiri')
      end
    end

    context 'with non-parseable lines' do
      let(:parseable_output) do
        <<~OUTPUT
          Fetching gem metadata from https://rubygems.org/...
          nokogiri (newest 1.16.4, installed 1.16.2)
          Some random message
        OUTPUT
      end

      it 'ignores non-parseable lines' do
        gems = checker.outdated_gems
        expect(gems.length).to eq(1)
        expect(gems.first.name).to eq('nokogiri')
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::RubygemsApi do
  let(:api) { described_class.new }

  describe '#fetch_versions' do
    let(:versions_response) do
      [
        { 'number' => '1.16.4', 'created_at' => '2024-04-10T12:00:00Z' },
        { 'number' => '1.16.3', 'created_at' => '2024-03-15T12:00:00Z' }
      ].to_json
    end

    before do
      stub_request(:get, 'https://rubygems.org/api/v1/versions/nokogiri.json')
        .to_return(status: 200, body: versions_response)
    end

    it 'fetches versions from RubyGems API' do
      versions = api.fetch_versions('nokogiri')
      expect(versions.length).to eq(2)
      expect(versions.first['number']).to eq('1.16.4')
    end
  end

  describe '#fetch_version_info' do
    let(:versions_response) do
      [
        { 'number' => '1.16.4', 'created_at' => '2024-04-10T12:00:00Z' },
        { 'number' => '1.16.3', 'created_at' => '2024-03-15T12:00:00Z' }
      ].to_json
    end

    before do
      stub_request(:get, 'https://rubygems.org/api/v1/versions/nokogiri.json')
        .to_return(status: 200, body: versions_response)
    end

    it 'returns version info for specific version' do
      info = api.fetch_version_info('nokogiri', '1.16.4')
      expect(info['number']).to eq('1.16.4')
      expect(info['created_at']).to eq('2024-04-10T12:00:00Z')
    end

    it 'returns nil for non-existent version' do
      info = api.fetch_version_info('nokogiri', '9.9.9')
      expect(info).to be_nil
    end
  end

  describe '#version_age_days' do
    let(:created_at) { (Time.now - (10 * 86_400)).utc.iso8601 }
    let(:versions_response) do
      [{ 'number' => '1.0.0', 'created_at' => created_at }].to_json
    end

    before do
      stub_request(:get, 'https://rubygems.org/api/v1/versions/test-gem.json')
        .to_return(status: 200, body: versions_response)
    end

    it 'calculates age in days' do
      age = api.version_age_days('test-gem', '1.0.0')
      expect(age).to be_within(1).of(10)
    end

    it 'returns nil for non-existent version' do
      age = api.version_age_days('test-gem', '9.9.9')
      expect(age).to be_nil
    end
  end

  describe 'error handling' do
    it 'raises ApiError on HTTP failure' do
      stub_request(:get, 'https://rubygems.org/api/v1/versions/bad-gem.json')
        .to_return(status: 404, body: 'Not Found')

      expect { api.fetch_versions('bad-gem') }
        .to raise_error(BundleSafeUpdate::RubygemsApi::ApiError, /404/)
    end

    it 'raises ApiError on invalid JSON' do
      stub_request(:get, 'https://rubygems.org/api/v1/versions/bad-json.json')
        .to_return(status: 200, body: 'not valid json')

      expect { api.fetch_versions('bad-json') }
        .to raise_error(BundleSafeUpdate::RubygemsApi::ApiError, /Invalid JSON/)
    end
  end
end

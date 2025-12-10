# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::Config do
  let(:home_config_path) { File.join(Dir.home, '.bundle-safe-update.yml') }
  let(:local_config_path) { File.join(Dir.pwd, '.bundle-safe-update.yml') }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(home_config_path).and_return(false)
    allow(File).to receive(:exist?).with(local_config_path).and_return(false)
  end

  describe 'defaults' do
    it 'uses default cooldown_days of 14' do
      config = described_class.new
      expect(config.cooldown_days).to eq(14)
    end

    it 'uses empty ignore_gems by default' do
      config = described_class.new
      expect(config.ignore_gems).to eq([])
    end

    it 'uses empty ignore_prefixes by default' do
      config = described_class.new
      expect(config.ignore_prefixes).to eq([])
    end

    it 'uses verbose false by default' do
      config = described_class.new
      expect(config.verbose).to be(false)
    end
  end

  describe 'global config' do
    before do
      allow(File).to receive(:exist?).with(home_config_path).and_return(true)
      allow(YAML).to receive(:safe_load_file).with(home_config_path).and_return({
                                                                                  'cooldown_days' => 21,
                                                                                  'ignore_gems' => %w[rails]
                                                                                })
    end

    it 'loads cooldown_days from global config' do
      config = described_class.new
      expect(config.cooldown_days).to eq(21)
    end

    it 'loads ignore_gems from global config' do
      config = described_class.new
      expect(config.ignore_gems).to eq(%w[rails])
    end
  end

  describe 'local config overrides global' do
    before do
      allow(File).to receive(:exist?).with(home_config_path).and_return(true)
      allow(File).to receive(:exist?).with(local_config_path).and_return(true)
      allow(YAML).to receive(:safe_load_file).with(home_config_path).and_return({
                                                                                  'cooldown_days' => 21,
                                                                                  'ignore_gems' => %w[rails]
                                                                                })
      allow(YAML).to receive(:safe_load_file).with(local_config_path).and_return({
                                                                                   'cooldown_days' => 7,
                                                                                   'ignore_prefixes' => %w[mycompany-]
                                                                                 })
    end

    it 'uses local cooldown_days over global' do
      config = described_class.new
      expect(config.cooldown_days).to eq(7)
    end

    it 'uses local ignore_prefixes' do
      config = described_class.new
      expect(config.ignore_prefixes).to eq(%w[mycompany-])
    end

    it 'replaces ignore_gems from local config' do
      config = described_class.new
      expect(config.ignore_gems).to eq(%w[rails])
    end
  end

  describe 'CLI overrides' do
    before do
      allow(File).to receive(:exist?).with(local_config_path).and_return(true)
      allow(YAML).to receive(:safe_load_file).with(local_config_path).and_return({
                                                                                   'cooldown_days' => 7
                                                                                 })
    end

    it 'CLI cooldown overrides config file' do
      config = described_class.new(cooldown: 30)
      expect(config.cooldown_days).to eq(30)
    end

    it 'CLI verbose overrides config file' do
      config = described_class.new(verbose: true)
      expect(config.verbose).to be(true)
    end
  end

  describe 'custom config file' do
    let(:custom_path) { '/tmp/custom-config.yml' }

    before do
      allow(File).to receive(:exist?).with(custom_path).and_return(true)
      allow(YAML).to receive(:safe_load_file).with(custom_path).and_return({
                                                                             'cooldown_days' => 42
                                                                           })
    end

    it 'loads custom config file' do
      config = described_class.new(config: custom_path)
      expect(config.cooldown_days).to eq(42)
    end
  end

  describe '#ignored?' do
    before do
      allow(File).to receive(:exist?).with(local_config_path).and_return(true)
      allow(YAML).to receive(:safe_load_file).with(local_config_path).and_return({
                                                                                   'ignore_gems' => %w[rails sidekiq],
                                                                                   'ignore_prefixes' => %w[mycompany-
                                                                                                           internal-]
                                                                                 })
    end

    let(:config) { described_class.new }

    it 'returns true for gems in ignore_gems' do
      expect(config.ignored?('rails')).to be(true)
      expect(config.ignored?('sidekiq')).to be(true)
    end

    it 'returns true for gems matching ignore_prefixes' do
      expect(config.ignored?('mycompany-auth')).to be(true)
      expect(config.ignored?('internal-utils')).to be(true)
    end

    it 'returns false for non-ignored gems' do
      expect(config.ignored?('nokogiri')).to be(false)
      expect(config.ignored?('puma')).to be(false)
    end
  end

  describe 'invalid YAML handling' do
    before do
      allow(File).to receive(:exist?).with(local_config_path).and_return(true)
      allow(YAML).to receive(:safe_load_file)
        .with(local_config_path)
        .and_raise(Psych::SyntaxError.new('file', 1, 1, 0, 'bad yaml', 'context'))
    end

    it 'falls back to defaults on invalid YAML' do
      expect { described_class.new }.to output(/Warning/).to_stderr
      config = described_class.new
      expect(config.cooldown_days).to eq(14)
    end
  end
end

# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::ColorOutput do
  let(:test_class) do
    Class.new do
      include BundleSafeUpdate::ColorOutput

      def initialize(tty_mode)
        @tty_mode = tty_mode
      end

      private

      def tty?
        @tty_mode
      end
    end
  end

  describe '#colorize' do
    context 'when stdout is a tty' do
      let(:instance) { test_class.new(true) }

      it 'wraps text in green color codes' do
        expect(instance.green('test')).to eq("\e[32mtest\e[0m")
      end

      it 'wraps text in yellow color codes' do
        expect(instance.yellow('test')).to eq("\e[33mtest\e[0m")
      end

      it 'wraps text in red color codes' do
        expect(instance.red('test')).to eq("\e[31mtest\e[0m")
      end

      it 'wraps text in cyan color codes' do
        expect(instance.cyan('test')).to eq("\e[36mtest\e[0m")
      end
    end

    context 'when stdout is not a tty' do
      let(:instance) { test_class.new(false) }

      it 'returns text unchanged for green' do
        expect(instance.green('test')).to eq('test')
      end

      it 'returns text unchanged for yellow' do
        expect(instance.yellow('test')).to eq('test')
      end

      it 'returns text unchanged for red' do
        expect(instance.red('test')).to eq('test')
      end

      it 'returns text unchanged for cyan' do
        expect(instance.cyan('test')).to eq('test')
      end
    end
  end
end

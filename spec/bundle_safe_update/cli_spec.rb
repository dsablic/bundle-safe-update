# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::CLI do
  let(:cli) { described_class.new }

  describe 'exit codes' do
    it 'defines EXIT_SUCCESS as 0' do
      expect(described_class::EXIT_SUCCESS).to eq(0)
    end

    it 'defines EXIT_VIOLATIONS as 1' do
      expect(described_class::EXIT_VIOLATIONS).to eq(1)
    end

    it 'defines EXIT_ERROR as 2' do
      expect(described_class::EXIT_ERROR).to eq(2)
    end
  end

  describe '#run' do
    let(:outdated_checker) { instance_double(BundleSafeUpdate::OutdatedChecker) }
    let(:gem_checker) { instance_double(BundleSafeUpdate::GemChecker) }

    before do
      allow(BundleSafeUpdate::OutdatedChecker).to receive(:new).and_return(outdated_checker)
      allow(BundleSafeUpdate::GemChecker).to receive(:new).and_return(gem_checker)

      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with(File.join(Dir.home, '.bundle-safe-update.yml'))
        .and_return(false)
      allow(File).to receive(:exist?)
        .with(File.join(Dir.pwd, '.bundle-safe-update.yml'))
        .and_return(false)
    end

    context 'with no outdated gems' do
      before do
        allow(outdated_checker).to receive(:outdated_gems).and_return([])
      end

      it 'returns success' do
        expect(cli.run([])).to eq(0)
      end

      it 'outputs JSON with ok: true when --json flag' do
        expect { cli.run(['--json']) }
          .to output(/"ok": true/).to_stdout
      end
    end

    context 'with allowed gems' do
      let(:gem_info) do
        BundleSafeUpdate::OutdatedChecker::OutdatedGem.new(
          name: 'rails',
          current_version: '7.0.8',
          newest_version: '7.1.3.2'
        )
      end

      let(:check_result) do
        BundleSafeUpdate::GemChecker::CheckResult.new(
          name: 'rails',
          version: '7.1.3.2',
          age_days: 42,
          allowed: true,
          reason: 'satisfies minimum age'
        )
      end

      before do
        allow(outdated_checker).to receive(:outdated_gems).and_return([gem_info])
        allow(gem_checker).to receive(:check_all).and_return([check_result])
      end

      it 'returns success' do
        expect(cli.run([])).to eq(0)
      end

      it 'outputs OK message' do
        expect { cli.run([]) }
          .to output(/OK: rails.*satisfies minimum age/).to_stdout
      end
    end

    context 'with blocked gems' do
      let(:gem_info) do
        BundleSafeUpdate::OutdatedChecker::OutdatedGem.new(
          name: 'nokogiri',
          current_version: '1.16.2',
          newest_version: '1.16.4'
        )
      end

      let(:check_result) do
        BundleSafeUpdate::GemChecker::CheckResult.new(
          name: 'nokogiri',
          version: '1.16.4',
          age_days: 3,
          allowed: false,
          reason: 'too new'
        )
      end

      before do
        allow(outdated_checker).to receive(:outdated_gems).and_return([gem_info])
        allow(gem_checker).to receive(:check_all).and_return([check_result])
      end

      it 'returns violations exit code' do
        expect(cli.run([])).to eq(1)
      end

      it 'outputs BLOCKED message' do
        expect { cli.run([]) }
          .to output(/BLOCKED: nokogiri.*published 3 days ago/).to_stdout
      end

      it 'outputs violation count' do
        expect { cli.run([]) }
          .to output(/1 gem\(s\) violate minimum release age/).to_stdout
      end

      context 'with --json flag' do
        it 'outputs JSON with blocked gems' do
          output = capture_stdout { cli.run(['--json']) }
          json = JSON.parse(output)

          expect(json['ok']).to be(false)
          expect(json['blocked'].length).to eq(1)
          expect(json['blocked'].first['name']).to eq('nokogiri')
          expect(json['blocked'].first['age_days']).to eq(3)
        end
      end
    end

    context 'with --dry-run flag' do
      it 'returns success without checking gems' do
        expect(outdated_checker).not_to receive(:outdated_gems)
        expect(cli.run(['--dry-run'])).to eq(0)
      end

      it 'outputs configuration' do
        expect { cli.run(['--dry-run']) }
          .to output(/Cooldown days: 14.*Update: false/m).to_stdout
      end
    end

    context 'with --cooldown flag' do
      before do
        allow(outdated_checker).to receive(:outdated_gems).and_return([])
      end

      it 'uses custom cooldown days' do
        expect { cli.run(['--dry-run', '--cooldown', '30']) }
          .to output(/Cooldown days: 30/).to_stdout
      end
    end

    context 'on error' do
      before do
        allow(outdated_checker).to receive(:outdated_gems)
          .and_raise(StandardError, 'Something went wrong')
      end

      it 'returns error exit code' do
        expect(cli.run([])).to eq(2)
      end

      it 'outputs error message' do
        expect { cli.run([]) }
          .to output(/Error: Something went wrong/).to_stderr
      end
    end

    context 'with --update flag' do
      let(:allowed_gem) do
        BundleSafeUpdate::OutdatedChecker::OutdatedGem.new(
          name: 'rails',
          current_version: '7.0.8',
          newest_version: '7.1.3.2'
        )
      end

      let(:blocked_gem) do
        BundleSafeUpdate::OutdatedChecker::OutdatedGem.new(
          name: 'nokogiri',
          current_version: '1.16.2',
          newest_version: '1.16.4'
        )
      end

      let(:allowed_result) do
        BundleSafeUpdate::GemChecker::CheckResult.new(
          name: 'rails',
          version: '7.1.3.2',
          age_days: 42,
          allowed: true,
          reason: 'satisfies minimum age'
        )
      end

      let(:blocked_result) do
        BundleSafeUpdate::GemChecker::CheckResult.new(
          name: 'nokogiri',
          version: '1.16.4',
          age_days: 3,
          allowed: false,
          reason: 'too new'
        )
      end

      context 'when there are allowed gems' do
        before do
          allow(outdated_checker).to receive(:outdated_gems).and_return([allowed_gem])
          allow(gem_checker).to receive(:check_all).and_return([allowed_result])
        end

        it 'runs bundle update for allowed gems' do
          expect(cli).to receive(:system)
            .with('bundle', 'update', 'rails')
            .and_return(true)
          cli.run(['--update'])
        end

        it 'outputs success message when update succeeds' do
          allow(cli).to receive(:system).and_return(true)
          expect { cli.run(['--update']) }
            .to output(/Bundle updated successfully/).to_stdout
        end

        it 'outputs failure message when update fails' do
          allow(cli).to receive(:system).and_return(false)
          expect { cli.run(['--update']) }
            .to output(/Bundle update failed/).to_stdout
        end
      end

      context 'when there are mixed allowed and blocked gems' do
        before do
          allow(outdated_checker).to receive(:outdated_gems)
            .and_return([allowed_gem, blocked_gem])
          allow(gem_checker).to receive(:check_all)
            .and_return([allowed_result, blocked_result])
        end

        it 'runs bundle update only for allowed gems' do
          expect(cli).to receive(:system)
            .with('bundle', 'update', 'rails')
            .and_return(true)
          cli.run(['--update'])
        end

        it 'outputs skipped gems message' do
          allow(cli).to receive(:system).and_return(true)
          expect { cli.run(['--update']) }
            .to output(/Skipped 1 blocked gem\(s\): nokogiri/).to_stdout
        end

        it 'returns violations exit code even after update' do
          allow(cli).to receive(:system).and_return(true)
          expect(cli.run(['--update'])).to eq(1)
        end
      end

      context 'when all gems are blocked' do
        before do
          allow(outdated_checker).to receive(:outdated_gems).and_return([blocked_gem])
          allow(gem_checker).to receive(:check_all).and_return([blocked_result])
        end

        it 'does not run bundle update' do
          expect(cli).not_to receive(:system)
          cli.run(['--update'])
        end
      end

      context 'when no outdated gems' do
        before do
          allow(outdated_checker).to receive(:outdated_gems).and_return([])
        end

        it 'does not run bundle update' do
          expect(cli).not_to receive(:system)
          cli.run(['--update'])
        end
      end
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end

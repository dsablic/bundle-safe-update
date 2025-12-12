# frozen_string_literal: true

RSpec.describe BundleSafeUpdate::AuditChecker do
  let(:checker) { described_class.new(executor: executor) }
  let(:executor) { ->(_cmd) { [stdout, stderr, status] } }
  let(:stderr) { '' }

  describe '#check' do
    context 'when bundler-audit is not installed' do
      let(:checker) { described_class.new }

      before do
        allow(Open3).to receive(:capture3)
          .with('bundle', 'audit', '--version')
          .and_raise(Errno::ENOENT)
      end

      it 'returns unavailable result' do
        result = checker.check
        expect(result.available).to be(false)
        expect(result.vulnerabilities).to eq([])
      end
    end

    context 'when no vulnerabilities found' do
      let(:stdout) { "No vulnerabilities found\n" }
      let(:status) { instance_double(Process::Status, success?: true) }

      before do
        allow(Open3).to receive(:capture3)
          .with('bundle', 'audit', '--version')
          .and_return(['bundler-audit 0.9.1', '', instance_double(Process::Status, success?: true)])
      end

      it 'returns empty vulnerabilities' do
        result = checker.check
        expect(result.available).to be(true)
        expect(result.vulnerabilities).to eq([])
        expect(result.error).to be_nil
      end
    end

    context 'when vulnerabilities found' do
      let(:stdout) do
        <<~OUTPUT
          Name: actionpack
          Version: 7.0.8
          CVE: CVE-2024-1234
          Title: Possible XSS vulnerability
          Solution: upgrade to >= 7.0.8.1

          Name: puma
          Version: 6.4.0
          CVE: CVE-2024-5678
          Title: HTTP request smuggling
          Solution: upgrade to >= 6.4.1

          Vulnerabilities found!
        OUTPUT
      end
      let(:status) { instance_double(Process::Status, success?: false) }

      before do
        allow(Open3).to receive(:capture3)
          .with('bundle', 'audit', '--version')
          .and_return(['bundler-audit 0.9.1', '', instance_double(Process::Status, success?: true)])
      end

      it 'returns parsed vulnerabilities' do
        result = checker.check
        expect(result.available).to be(true)
        expect(result.vulnerabilities.length).to eq(2)
      end

      it 'parses vulnerability details' do
        result = checker.check
        vuln = result.vulnerabilities.first

        expect(vuln.gem_name).to eq('actionpack')
        expect(vuln.cve).to eq('CVE-2024-1234')
        expect(vuln.title).to eq('Possible XSS vulnerability')
        expect(vuln.solution).to eq('upgrade to >= 7.0.8.1')
      end
    end

    context 'when audit command fails with error' do
      let(:stdout) { '' }
      let(:stderr) { 'Failed to fetch advisory database' }
      let(:status) { instance_double(Process::Status, success?: false) }

      before do
        allow(Open3).to receive(:capture3)
          .with('bundle', 'audit', '--version')
          .and_return(['bundler-audit 0.9.1', '', instance_double(Process::Status, success?: true)])
      end

      it 'returns error result' do
        result = checker.check
        expect(result.available).to be(true)
        expect(result.error).to eq('Failed to fetch advisory database')
      end
    end
  end
end

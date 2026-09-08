#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_file="$repo_root/.github/workflows/build-and-release.yml"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "$path" ]]; then
    echo "Missing executable bit: $path" >&2
    exit 1
  fi
}

require_file "$workflow_file"
require_file "$repo_root/scripts/ci/run_code_analysis.sh"
require_file "$repo_root/scripts/ci/build_matrix_artifacts.sh"
require_file "$repo_root/scripts/ci/setup_platform_deps.sh"
require_file "$repo_root/scripts/ci/compute_release_metadata.sh"
require_file "$repo_root/scripts/ci/build_linux_source_packages.sh"
require_file "$repo_root/scripts/ci/publish_launchpad_ppa.sh"
require_file "$repo_root/scripts/ci/verify_ppa_signing.sh"
require_file "$repo_root/scripts/ci/publish_obs_package.sh"
require_file "$repo_root/scripts/package-linux-payload.sh"
require_file "$repo_root/scripts/package-debian-source.sh"
require_file "$repo_root/scripts/package-rpm-source.sh"
require_file "$repo_root/debian/rules"
require_file "$repo_root/packaging/rpm/xworkmate.spec"

require_exec "$repo_root/scripts/ci/run_code_analysis.sh"
require_exec "$repo_root/scripts/ci/build_matrix_artifacts.sh"
require_exec "$repo_root/scripts/ci/setup_platform_deps.sh"
require_exec "$repo_root/scripts/ci/compute_release_metadata.sh"
require_exec "$repo_root/scripts/ci/build_linux_source_packages.sh"
require_exec "$repo_root/scripts/ci/publish_launchpad_ppa.sh"
require_exec "$repo_root/scripts/ci/verify_ppa_signing.sh"
require_exec "$repo_root/scripts/ci/publish_obs_package.sh"
require_exec "$repo_root/scripts/package-linux-payload.sh"
require_exec "$repo_root/scripts/package-debian-source.sh"
require_exec "$repo_root/scripts/package-rpm-source.sh"
require_exec "$repo_root/debian/rules"

ruby - "$workflow_file" <<'RUBY'
require 'yaml'

workflow_path = ARGV.fetch(0)
data = YAML.load_file(workflow_path)

expected_jobs = %w[prepare verify build release]
missing_jobs = expected_jobs.reject { |job| data.fetch('jobs', {}).key?(job) }
abort("Missing workflow jobs: #{missing_jobs.join(', ')}") unless missing_jobs.empty?

# The main-branch release rule lives in the job condition and in the extracted
# determine_release_mode.sh, not in an inline `run:` body.
prepare_job = data.fetch('jobs').fetch('prepare')
prepare_text = [
  prepare_job['if'],
  *prepare_job.fetch('steps', []).map { |step| step['run'] }
].compact.join("\n")
release_mode_script = File.join(File.dirname(File.dirname(workflow_path)), 'scripts', 'determine_release_mode.sh')
prepare_text += File.read(release_mode_script) if File.exist?(release_mode_script)
abort('prepare job must release from main.') unless prepare_text.include?('refs/heads/main')

build_job = data.fetch('jobs').fetch('build')
matrix = build_job.fetch('strategy', {}).fetch('matrix', {}).fetch('include', [])
platforms = matrix.map { |entry| entry['platform'] }.compact.to_h { |platform| [platform, true] }.keys
expected_platforms = %w[linux windows macos ios android]
missing_platforms = expected_platforms.reject { |platform| platforms.include?(platform) }
abort("Missing build matrix platforms: #{missing_platforms.join(', ')}") unless missing_platforms.empty?

text = File.read(workflow_path)
required_snippets = [
  'bash ./scripts/ci/run_flutter_ci_suite.sh',
  'bash ./scripts/ci/build_matrix_artifacts.sh',
  'bash ./scripts/ci/setup_platform_deps.sh',
  'bash ./scripts/ci/compute_release_metadata.sh',
  'needs.prepare.outputs.should_release == \'true\'',
  'actions/upload-artifact',
  'actions/download-artifact',
  'bash ./scripts/ci/build_linux_source_packages.sh',
  'bash ./scripts/ci/verify_ppa_signing.sh',
  './.github/actions/publish-launchpad-ppa',
  './.github/actions/publish-obs-package'
]
missing_snippets = required_snippets.reject { |snippet| text.include?(snippet) }
abort("Missing workflow references: #{missing_snippets.join(', ')}") unless missing_snippets.empty?

release_job = data.fetch('jobs').fetch('release')
release_targets = release_job.fetch('strategy', {}).fetch('matrix', {}).fetch('include', [])
                             .map { |entry| entry['target'] }.compact
expected_targets = %w[github_release launchpad_ppa obs_rpm]
missing_targets = expected_targets.reject { |target| release_targets.include?(target) }
abort("Missing release targets: #{missing_targets.join(', ')}") unless missing_targets.empty?

puts 'Workflow structure check passed.'
RUBY

echo "Monitoring checks passed for build-and-release workflow."

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

require_exec "$repo_root/scripts/ci/run_code_analysis.sh"
require_exec "$repo_root/scripts/ci/build_matrix_artifacts.sh"
require_exec "$repo_root/scripts/ci/setup_platform_deps.sh"
require_exec "$repo_root/scripts/ci/compute_release_metadata.sh"

ruby - "$workflow_file" <<'RUBY'
require 'yaml'

workflow_path = ARGV.fetch(0)
data = YAML.load_file(workflow_path)

expected_jobs = %w[prepare verify build release]
missing_jobs = expected_jobs.reject { |job| data.fetch('jobs', {}).key?(job) }
abort("Missing workflow jobs: #{missing_jobs.join(', ')}") unless missing_jobs.empty?

build_job = data.fetch('jobs').fetch('build')
matrix = build_job.fetch('strategy', {}).fetch('matrix', {}).fetch('include', [])
platforms = matrix.map { |entry| entry['platform'] }.compact.to_h { |platform| [platform, true] }.keys
expected_platforms = %w[linux windows macos ios android]
missing_platforms = expected_platforms.reject { |platform| platforms.include?(platform) }
abort("Missing build matrix platforms: #{missing_platforms.join(', ')}") unless missing_platforms.empty?

text = File.read(workflow_path)
required_snippets = [
  'bash ./scripts/ci/run_code_analysis.sh',
  'bash ./scripts/ci/build_matrix_artifacts.sh',
  'bash ./scripts/ci/setup_platform_deps.sh',
  'bash ./scripts/ci/compute_release_metadata.sh',
  'actions/upload-artifact',
  'actions/download-artifact'
]
missing_snippets = required_snippets.reject { |snippet| text.include?(snippet) }
abort("Missing workflow references: #{missing_snippets.join(', ')}") unless missing_snippets.empty?

puts 'Workflow structure check passed.'
RUBY

echo "Monitoring checks passed for build-and-release workflow."

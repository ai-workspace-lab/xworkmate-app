#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_REF:-}" == refs/tags/v* || "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" || "${GITHUB_REF:-}" == "refs/heads/main" || "${GITHUB_REF:-}" == refs/heads/release/* ]]; then
  echo "should_release=true" >> "$GITHUB_OUTPUT"
else
  echo "should_release=false" >> "$GITHUB_OUTPUT"
fi

if [[ "${ENABLE_TESTFLIGHT_INPUT:-}" == "true" || "${ENABLE_TESTFLIGHT_VAR:-}" == "true" ]]; then
  echo "testflight_enabled=true" >> "$GITHUB_OUTPUT"
else
  echo "testflight_enabled=false" >> "$GITHUB_OUTPUT"
fi

if [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" && "${ENABLE_GITHUB_RELEASE_INPUT:-}" == "false" ]]; then
  echo "github_release_enabled=false" >> "$GITHUB_OUTPUT"
else
  echo "github_release_enabled=true" >> "$GITHUB_OUTPUT"
fi

#!/usr/bin/env bash
# Write SHA / platform / tool versions for CI artifacts and logs.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-build/ci/context.txt}
mkdir -p "$(dirname "$out")"
{
  echo "sha=${GITHUB_SHA:-$(git rev-parse HEAD)}"
  echo "ref=${GITHUB_REF:-$(git rev-parse --abbrev-ref HEAD)}"
  echo "event=${GITHUB_EVENT_NAME:-local}"
  echo "job=${GITHUB_JOB:-local}"
  echo "runner_os=${RUNNER_OS:-$(uname -s)}"
  echo "runner_arch=${RUNNER_ARCH:-$(uname -m)}"
  echo "uname=$(uname -a)"
  if command -v flutter >/dev/null 2>&1; then
    flutter --version
  fi
  if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version
  fi
} | tee "$out"

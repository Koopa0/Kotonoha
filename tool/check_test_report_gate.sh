#!/usr/bin/env bash
# Permanent red→green proof for the Flutter test-report floor.
# Fault fixtures must stay red; a healthy report must stay green.
# This is not project-wide mutation — it only guards this new gate.
set -euo pipefail
cd "$(dirname "$0")/.."

py=tool/require_flutter_test_report.py
data=tool/testdata/flutter_test_reports

expect_green() {
  local name=$1
  shift
  if ! python3 "$py" "$@"; then
    echo "EXPECTED GREEN: $name went red" >&2
    exit 1
  fi
  echo "green as required: $name"
}

expect_red() {
  local name=$1
  shift
  if python3 "$py" "$@"; then
    echo "EXPECTED RED: $name stayed green" >&2
    exit 1
  fi
  echo "red as required: $name"
}

expect_green healthy \
  --report "$data/healthy.jsonl" \
  --min-passed 1 \
  --forbid-skip \
  --require-name 'actual test'

expect_red empty_success \
  --report "$data/empty_success.jsonl" \
  --min-passed 1 \
  --forbid-skip \
  --require-name 'actual test'

expect_red hidden_only \
  --report "$data/hidden_only.jsonl" \
  --min-passed 1 \
  --forbid-skip

expect_red all_skipped \
  --report "$data/all_skipped.jsonl" \
  --min-passed 1 \
  --forbid-skip \
  --require-name 'actual OS partial append followed by retry preserves attempt'

expect_red failed \
  --report "$data/failed.jsonl" \
  --min-passed 1 \
  --forbid-skip \
  --require-name 'actual test'

expect_red missing_file \
  --report "$data/does-not-exist.jsonl" \
  --min-passed 1

expect_red renamed_required_name \
  --report "$data/healthy.jsonl" \
  --min-passed 1 \
  --forbid-skip \
  --require-name 'wrong name'

echo "test-report gate self-check: healthy green, fault fixtures red"

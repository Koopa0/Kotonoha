#!/usr/bin/env bash
# Isolated OS RLIMIT_FSIZE probe. Process-wide limit — this file alone.
set -euo pipefail
cd "$(dirname "$0")/.."

probe=test/services/file_analytics_log_os_partial_test.dart
if [[ ! -f $probe ]]; then
  echo "BLOCKED: $probe is missing" >&2
  exit 1
fi
if [[ ${KOTONOHA_RUN_OS_PARTIAL:-} != 1 ]]; then
  echo "BLOCKED: KOTONOHA_RUN_OS_PARTIAL=1 is required; refusing a skipped no-op" >&2
  exit 1
fi
case $(uname -s) in
Linux | Darwin) ;;
*)
  echo "BLOCKED: OS partial-write probe needs Linux or macOS libc/setrlimit" >&2
  exit 1
  ;;
esac

mkdir -p build/ci
report=build/ci/os_partial.jsonl
rm -f "$report"

# One dedicated flutter test process — no other writers in this suite.
flutter test "$probe" \
  --reporter expanded \
  --file-reporter "json:$report"

python3 tool/require_flutter_test_report.py \
  --report "$report" \
  --min-passed 1 \
  --forbid-skip \
  --require-name 'actual OS partial append followed by retry preserves attempt'

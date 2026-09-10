#!/usr/bin/env bash
# Real-bootstrap integration tests on an attached Android device/emulator.
# Refuses host / desktop fallback when the platform is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

suite=integration_test/app_test.dart
if [[ ! -f $suite ]]; then
  echo "BLOCKED: $suite is missing" >&2
  exit 1
fi
if grep -q SilentSpeechService "$suite"; then
  echo "BLOCKED: $suite must keep native plugins; SilentSpeechService is a host stand-in" >&2
  exit 1
fi
if ! grep -q 'app.bootstrap()' "$suite"; then
  echo "BLOCKED: $suite must call the real bootstrap()" >&2
  exit 1
fi

if [[ $(uname -s) == Linux && ! -e /dev/kvm ]]; then
  echo "BLOCKED: /dev/kvm is missing; emulator hardware acceleration unavailable. Refusing host fallback." >&2
  exit 1
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "BLOCKED: adb is missing; Android platform unavailable. Refusing host fallback." >&2
  exit 1
fi

mapfile -t serials < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
if [[ ${#serials[@]} -eq 0 ]]; then
  echo "BLOCKED: no Android emulator/device in 'device' state. Refusing host fallback." >&2
  adb devices -l >&2 || true
  exit 1
fi
serial=${serials[0]}
echo "android_serial=$serial"

mkdir -p build/ci
report=build/ci/android_integration.jsonl
rm -f "$report"

dump_logcat() {
  adb -s "$serial" logcat -d >build/ci/logcat.txt || true
}
trap dump_logcat EXIT

flutter test "$suite" \
  --device-id "$serial" \
  --reporter expanded \
  --file-reporter "json:$report"

python3 tool/require_flutter_test_report.py \
  --report "$report" \
  --min-passed 3 \
  --forbid-skip \
  --require-name 'app launches and the home screen renders without crashing' \
  --require-name 'real navigation: home → lessons → study a row → reach its test' \
  --require-name 'real navigation: the 五十音図 grid renders the full row span'

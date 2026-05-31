#!/usr/bin/env bash
#
# Verifies (or with --fix, inserts) the MIT SPDX license header at the top of
# every Dart source file. Run in CI to keep the header on every file:
#
#   tool/check_license_headers.sh          # check only — exits 1 if any missing
#   tool/check_license_headers.sh --fix    # prepend the header where missing
#
set -euo pipefail
cd "$(dirname "$0")/.."

LINE1='// Copyright (c) 2026 Koopa'
LINE2='// SPDX-License-Identifier: MIT'

# Dart sources we own. Generated files (*.g.dart, *.freezed.dart) are exempt.
mapfile -t files < <(
  find lib test integration_test tool -name '*.dart' \
    ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null | sort
)

missing=()
for f in "${files[@]}"; do
  if [[ "$(head -n1 "$f")" != "$LINE1" ]]; then
    missing+=("$f")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "license headers: OK (${#files[@]} files)"
  exit 0
fi

if [[ "${1:-}" == "--fix" ]]; then
  for f in "${missing[@]}"; do
    # Prepend via a temp file so the original's trailing newline is preserved
    # (command substitution would strip it and trip eol_at_end_of_file).
    { printf '%s\n%s\n\n' "$LINE1" "$LINE2"; cat "$f"; } > "$f.tmp"
    mv "$f.tmp" "$f"
    echo "fixed: $f"
  done
  echo "license headers: inserted into ${#missing[@]} file(s)"
  exit 0
fi

echo "license headers: MISSING in ${#missing[@]} file(s):" >&2
printf '  %s\n' "${missing[@]}" >&2
echo "run: tool/check_license_headers.sh --fix" >&2
exit 1

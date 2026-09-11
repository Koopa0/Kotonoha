#!/usr/bin/env bash
# Host compile of official SnapshotSafStore / SnapshotSafWrite against
# the Activity / Channel stubs in this directory. Not Gradle
# testDebugUnitTest, and not a device run. SnapshotSafWriteTest stays
# in standard src/test (pure JVM). SnapshotSafStoreTest lives here
# because it needs the stubs, not mockable android.jar.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run.sh [--kotlinc PATH] [--kotlin PATH]

Finds kotlinc / kotlin on PATH, or from --kotlinc / --kotlin, or from
$KOTLINC / $KOTLIN. Compiles official snapshot sources plus host stubs.
EOF
}

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
kotlinc_bin="${KOTLINC:-}"
kotlin_bin="${KOTLIN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kotlinc)
      kotlinc_bin="$2"
      shift 2
      ;;
    --kotlin)
      kotlin_bin="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

find_tool() {
  local name="$1"
  local override="$2"
  if [[ -n "$override" ]]; then
    if [[ ! -x "$override" ]]; then
      echo "$name is not an executable file: $override" >&2
      exit 1
    fi
    printf '%s\n' "$override"
    return
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  echo "missing $name: put it on PATH or pass --$name" >&2
  exit 1
}

kotlinc_bin="$(find_tool kotlinc "$kotlinc_bin")"
kotlin_bin="$(find_tool kotlin "$kotlin_bin")"

lib="${KOTONOHA_SAF_HOST_LIB:-${TMPDIR:-/tmp}/kotonoha-saf-host-lib}"
mkdir -p "$lib"
junit_jar="$lib/junit-4.13.2.jar"
hamcrest_jar="$lib/hamcrest-core-1.3.jar"
if [[ ! -f "$junit_jar" ]]; then
  curl -fsSL -o "$junit_jar" \
    https://repo1.maven.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar
fi
if [[ ! -f "$hamcrest_jar" ]]; then
  curl -fsSL -o "$hamcrest_jar" \
    https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar
fi

out="$(mktemp -d "${TMPDIR:-/tmp}/kotonoha-saf-host.XXXXXX")"
cleanup() {
  rm -rf "$out"
}
trap cleanup EXIT

"$kotlinc_bin" \
  -cp "$junit_jar:$hamcrest_jar" \
  -d "$out" \
  "$root/android/app/src/main/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafWrite.kt" \
  "$root/android/app/src/main/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafStore.kt" \
  "$here"/stubs/android/app/Activity.kt \
  "$here"/stubs/android/content/Intent.kt \
  "$here"/stubs/android/content/ContentResolver.kt \
  "$here"/stubs/android/net/Uri.kt \
  "$here"/stubs/android/os/Handler.kt \
  "$here"/stubs/android/os/Looper.kt \
  "$here"/stubs/io/flutter/plugin/common/MethodCall.kt \
  "$here"/stubs/io/flutter/plugin/common/MethodChannel.kt \
  "$root/android/app/src/test/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafWriteTest.kt" \
  "$here/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafStoreTest.kt"

"$kotlin_bin" \
  -cp "$out:$junit_jar:$hamcrest_jar" \
  org.junit.runner.JUnitCore \
  com.koopa.kotonoha.snapshot.SnapshotSafStoreTest \
  com.koopa.kotonoha.snapshot.SnapshotSafWriteTest

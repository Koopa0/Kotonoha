#!/usr/bin/env bash
# Compile official SnapshotSafStore/Write with Activity/Channel stubs
# and run SnapshotSafStoreTest + SnapshotSafWriteTest. Not a device run.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../../.." && pwd)"
lib="${TMPDIR:-/tmp}/kotonoha-saf-host-lib"
out="${TMPDIR:-/tmp}/kotonoha-saf-host-out"
mkdir -p "$lib"
rm -rf "$out"
mkdir -p "$out"
if [[ ! -f "$lib/junit-4.13.2.jar" ]]; then
  curl -fsSL -o "$lib/junit-4.13.2.jar" \
    https://repo1.maven.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar
  curl -fsSL -o "$lib/hamcrest-core-1.3.jar" \
    https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar
fi
export PATH="/home/ubuntu/kotlinc/bin:${PATH}"
kotlinc \
  -cp "$lib/junit-4.13.2.jar:$lib/hamcrest-core-1.3.jar" \
  -d "$out" \
  "$root/android/app/src/main/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafWrite.kt" \
  "$root/android/app/src/main/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafStore.kt" \
  "$root"/android/app/src/testStandalone/stubs/android/app/Activity.kt \
  "$root"/android/app/src/testStandalone/stubs/android/content/Intent.kt \
  "$root"/android/app/src/testStandalone/stubs/android/content/ContentResolver.kt \
  "$root"/android/app/src/testStandalone/stubs/android/net/Uri.kt \
  "$root"/android/app/src/testStandalone/stubs/android/os/Handler.kt \
  "$root"/android/app/src/testStandalone/stubs/android/os/Looper.kt \
  "$root"/android/app/src/testStandalone/stubs/io/flutter/plugin/common/MethodCall.kt \
  "$root"/android/app/src/testStandalone/stubs/io/flutter/plugin/common/MethodChannel.kt \
  "$root/android/app/src/test/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafWriteTest.kt" \
  "$root/android/app/src/test/kotlin/com/koopa/kotonoha/snapshot/SnapshotSafStoreTest.kt"
kotlin \
  -cp "$out:$lib/junit-4.13.2.jar:$lib/hamcrest-core-1.3.jar" \
  org.junit.runner.JUnitCore \
  com.koopa.kotonoha.snapshot.SnapshotSafStoreTest \
  com.koopa.kotonoha.snapshot.SnapshotSafWriteTest

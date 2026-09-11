#!/usr/bin/env bash
# Free enough space for Android emulator userdata (~7.4 GB on emulator 37).
# Keep Java, Flutter, X11, and the Android SDK we actually launch.
# Do not use a bulk "remove large packages" sweep — that has deleted libX11.
set -euo pipefail

df -h /
echo "--- before cleanup ---"
du -sh /usr/share/dotnet /opt/ghc /usr/local/share/boost /usr/share/swift \
  /opt/hostedtoolcache/CodeQL /usr/local/lib/android/sdk/ndk \
  /usr/local/lib/android/sdk/ndk-bundle /usr/local/lib/android/sdk/cmake \
  2>/dev/null || true

sudo rm -rf \
  /usr/share/dotnet \
  /opt/ghc \
  /usr/local/share/boost \
  /usr/share/swift \
  /opt/hostedtoolcache/CodeQL \
  /usr/local/lib/android/sdk/ndk \
  /usr/local/lib/android/sdk/ndk-bundle \
  /usr/local/lib/android/sdk/cmake

# Preinstalled images we are not booting. Leave the API we asked the runner for.
sudo rm -rf /usr/local/lib/android/sdk/system-images/android-3{3,4,5,6}* \
  /usr/local/lib/android/sdk/system-images/android-28 \
  /usr/local/lib/android/sdk/system-images/android-30 \
  /usr/local/lib/android/sdk/system-images/android-31 \
  /usr/local/lib/android/sdk/system-images/android-32 \
  || true

echo "--- after cleanup ---"
df -h /

avail_kb=$(df --output=avail / | tail -1 | tr -d ' ')
# 10 GiB floor: emulator 37 asked for 7372 MB userdata on the first red run.
if ((avail_kb < 10485760)); then
  echo "BLOCKED: only ${avail_kb} KB free after cleanup; need >= 10 GiB for emulator userdata" >&2
  exit 1
fi
echo "free_kb=${avail_kb}"

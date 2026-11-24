#!/usr/bin/env bash
# Builds every release this machine can build and puts them in one folder.
#
#   tool/build_all.sh                 # Android + Linux into dist/<label>/
#   tool/build_all.sh android         # only some targets: android, linux
#   tool/build_all.sh -o ~/Releases   # another output folder
#
# Names match .github/workflows/release.yml:
#   cinemakom-<label>-android-arm64-v8a.apk    phones (and most TVs)
#   cinemakom-<label>-android-armeabi-v7a.apk  32-bit phones and TVs
#   cinemakom-<label>-android-x86_64.apk       emulators, Chromebooks
#   cinemakom-<label>-linux-x64.flatpak        Linux (tool/build_flatpak.sh)
# <label> is `git describe` (a tag such as v1.2.0, else the commit, with
# "-dirty" when there are uncommitted changes).
#
# Windows can't be built on Linux: the release workflow builds it. Apple
# platforms aren't supported (decision 2026-11-22). A target that fails doesn't stop the others; the script exits
# non-zero if any failed.
set -uo pipefail

cd "$(dirname "$0")/.."

out=""
targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out) out="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    android|linux) targets+=("$1"); shift ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

case "$(uname -s)" in
  Linux) possible=(android linux) ;;
  *) possible=(android) ;;
esac
[[ ${#targets[@]} -eq 0 ]] && targets=("${possible[@]}")

label="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
out="${out:-dist/$label}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

built=()
failed=()

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

build_android() {
  step "Android APKs (arm64-v8a, armeabi-v7a, x86_64)"
  fvm flutter build apk --release --split-per-abi || return 1
  for abi in arm64-v8a armeabi-v7a x86_64; do
    local apk="build/app/outputs/flutter-apk/app-${abi}-release.apk"
    [[ -f "$apk" ]] || { echo "Missing $apk" >&2; return 1; }
    cp "$apk" "$out/cinemakom-${label}-android-${abi}.apk"
    built+=("cinemakom-${label}-android-${abi}.apk")
  done
}

build_linux() {
  [[ "$(uname -s)" == Linux ]] || { echo "Linux builds need a Linux machine." >&2; return 1; }
  step "Linux (Flatpak)"
  tool/build_flatpak.sh -o "$out" --label "$label" || return 1
  built+=("cinemakom-${label}-linux-x64.flatpak")
}

# Java 24+ warns when Gradle's launcher loads its native library
# ("A restricted method in java.lang.System has been called"), and says a
# later Java will block it. Allow it. Gradle 9 needs Java 17+, which all know
# this option.
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }--enable-native-access=ALL-UNNAMED"

for target in "${targets[@]}"; do
  if "build_$target"; then :; else failed+=("$target"); fi
done

step "Done: $out"
width=10
for f in "${built[@]}"; do (( ${#f} > width )) && width=${#f}; done
for f in "${built[@]}"; do
  printf '  %-*s  %s\n' "$width" "$f" "$(du -h "$out/$f" | cut -f1)"
done
for t in windows; do
  printf '  %-*s  %s\n' "$width" "($t)" "not possible here: built by the release workflow"
done
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Failed: ${failed[*]}" >&2
  exit 1
fi

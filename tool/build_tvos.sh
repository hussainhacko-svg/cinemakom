#!/usr/bin/env bash
# Builds Cinemakom for Apple TV (tvOS) using the isolated flutter-tvos toolchain
# and lib/main_tvos.dart entrypoint. Leaves Android, iOS, macOS, Linux, and
# Windows builds completely untouched.
#
# Usage:
#   tool/build_tvos.sh simulator          # Debug build for Apple TV Simulator
#   tool/build_tvos.sh release            # Signed release build for Apple TV
#   tool/build_tvos.sh release --no-codesign
#   tool/build_tvos.sh run <sim-or-device-id>
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER_TVOS="${FLUTTER_TVOS:-$HOME/flutter-tvos/bin/flutter-tvos}"
if [[ ! -x "$FLUTTER_TVOS" ]]; then
  echo "flutter-tvos not found at $FLUTTER_TVOS" >&2
  echo "Clone https://github.com/fluttertv/flutter-tvos.git and run precache." >&2
  exit 1
fi

cmd="${1:-simulator}"
shift || true

case "$cmd" in
  simulator)
    "$FLUTTER_TVOS" build tvos --simulator --debug -t lib/main_tvos.dart "$@"
    ;;
  release)
    "$FLUTTER_TVOS" build tvos --release -t lib/main_tvos.dart "$@"
    ;;
  profile)
    "$FLUTTER_TVOS" build tvos --profile -t lib/main_tvos.dart "$@"
    ;;
  run)
    device="${1:-}"
    if [[ -z "$device" ]]; then
      echo "Usage: tool/build_tvos.sh run <device-id>" >&2
      "$FLUTTER_TVOS" devices
      exit 2
    fi
    shift
    "$FLUTTER_TVOS" run -d "$device" -t lib/main_tvos.dart "$@"
    ;;
  *)
    echo "Unknown command: $cmd (use simulator | release | profile | run <device-id>)" >&2
    exit 2
    ;;
esac

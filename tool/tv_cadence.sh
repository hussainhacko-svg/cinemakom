#!/bin/bash
# How evenly the real app (not a test) shows its frames on an Android TV:
# SurfaceFlinger's present times for the app's surface over 4 s, as the
# number of screen refreshes between frames. A 24 fps film on 60 Hz is a
# mix of 2× and 3×; 4× or more is a video frame shown too long (a hitch).
# Start playback on the TV first (docs/TV.md §9).
#
#   tool/tv_cadence.sh <tv-ip:port> [label]
set -euo pipefail
ADB="${ADB:-$HOME/Android/Sdk/platform-tools/adb} -s $1"
L=$($ADB shell dumpsys SurfaceFlinger --list | grep 'cinemakom.*\](BLAST)' | head -1)
[ -n "$L" ] || { echo "Cinemakom isn't on screen" >&2; exit 1; }
$ADB shell "dumpsys SurfaceFlinger --latency-clear '$L'" >/dev/null
sleep 4
$ADB shell "dumpsys SurfaceFlinger --latency '$L'" | awk -v name="${2:-frames}" '
NR == 1 { period = $1; next }
$2 != 0 && $2 < 9e18 { t[n++] = $2 }
END {
  for (i = 1; i < n; i++) { r = int((t[i] - t[i-1]) / period + 0.5); if (r > 0) h[r]++ }
  printf "%s: %d frames at %.2f ms; refreshes between frames:", name, n, period / 1e6
  for (r = 1; r <= 8; r++) if (h[r]) printf " %d×=%d", r, h[r]
  print ""
}'

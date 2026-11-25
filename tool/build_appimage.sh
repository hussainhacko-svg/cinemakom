#!/usr/bin/env bash
# Builds the Linux AppImage (docs/PACKAGING.md §3) in an Ubuntu 22.04
# container, so it runs on any Linux with glibc 2.35 or newer:
#
#   tool/build_appimage.sh             # dist/<label>/cinemakom-<label>-linux-x64.AppImage,
#                                      # and its .zsync (for AppImage updaters)
#   tool/build_appimage.sh -o ~/out    # another output folder
#   tool/build_appimage.sh --install   # also install it for this user, to try it
#   tool/build_appimage.sh --label v1.2.0 -- --build-name=1.2.0 --build-number=7
#                                      # CI: the file's label, and flags for
#                                      # `flutter build linux`
#
# Needs Docker. The first run builds the image (linux/appimage/Dockerfile:
# FFmpeg, mpv and the rest, and Flutter), which takes a while; later runs
# reuse it. IMAGE=<name> uses an image built elsewhere (CI caches it).
# <label> is `git describe`, as in tool/build_all.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

out=""
label=""
install=false
build_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out) out="$2"; shift 2 ;;
    --install) install=true; shift ;;
    --label) label="$2"; shift 2 ;;
    --) shift; build_args=("$@"); break ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

command -v docker >/dev/null || { echo "Docker is needed." >&2; exit 1; }

label="${label:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
out="${out:-dist/$label}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

flutter_version=$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' .fvmrc)
image="${IMAGE:-}"
if [[ -z "$image" ]]; then
  image=cinemakom-appimage
  printf '\n\033[1m== %s\033[0m\n' "Build image (Ubuntu 22.04, FFmpeg, mpv, Flutter $flutter_version)"
  docker build -t "$image" --build-arg FLUTTER_VERSION="$flutter_version" linux/appimage
fi

# The pub cache outlives the container, so packages download once.
docker run --rm \
  -v "$PWD:/src:ro" -v "$out:/out" \
  -v cinemakom-appimage-pub:/root/.pub-cache \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  "$image" bash /src/linux/appimage/build.sh "$label" "${build_args[@]}"

file="$out/cinemakom-${label}-linux-x64.AppImage"
if $install; then
  linux/appimage/install.sh --file "$file" --force
fi

#!/usr/bin/env bash
# Builds the Flatpak (docs/PACKAGING.md §3): the Flutter release bundle,
# then linux/flatpak/io.github.sharon_xa.cinemakom.yml, packed as one file:
#
#   tool/build_flatpak.sh              # dist/<label>/cinemakom-<label>-linux-x64.flatpak
#   tool/build_flatpak.sh -o ~/out     # another output folder
#   tool/build_flatpak.sh --install    # also install it for this user, to try it
#   tool/build_flatpak.sh --label v1.2.0 -- --build-name=1.2.0 --build-number=7
#                                      # CI: the file's label, and flags for
#                                      # `flutter build linux`
#
# Needs flatpak-builder (the command, or the org.flatpak.Builder app) and
# the GNOME SDK named in the manifest (`flatpak install flathub
# org.gnome.Sdk//51`). FLUTTER overrides the
# Flutter command (CI has plain `flutter`; here it's `fvm flutter`).
# <label> is `git describe`, as in tool/build_all.sh.
#
# Users install the file with: flatpak install --user <file>.flatpak
set -euo pipefail

cd "$(dirname "$0")/.."

app_id=io.github.sharon_xa.cinemakom
manifest=linux/flatpak/$app_id.yml
flutter=(${FLUTTER:-fvm flutter})
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
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

if command -v flatpak-builder >/dev/null; then
  builder=(flatpak-builder)
elif flatpak info org.flatpak.Builder >/dev/null 2>&1; then
  builder=(flatpak run org.flatpak.Builder)
else
  echo "flatpak-builder is missing: flatpak install flathub org.flatpak.Builder" >&2
  exit 1
fi
rt=$(sed -n "s/^runtime-version: '\(.*\)'/\1/p" "$manifest")
flatpak info "org.gnome.Sdk//$rt" >/dev/null 2>&1 || {
  echo "The GNOME SDK is missing: flatpak install flathub org.gnome.Sdk//$rt" >&2
  exit 1
}

label="${label:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
out="${out:-dist/$label}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
file="$out/cinemakom-${label}-linux-x64.flatpak"

printf '\n\033[1m== %s\033[0m\n' "Flutter release bundle"
"${flutter[@]}" build linux --release "${build_args[@]}"

printf '\n\033[1m== %s\033[0m\n' "Flatpak (libass, libplacebo, libmpv, the app)"
# Everything flatpak-builder makes stays in build/flatpak (gitignored).
"${builder[@]}" \
  --force-clean \
  --state-dir=build/flatpak/state \
  --repo=build/flatpak/repo \
  build/flatpak/app \
  "$manifest"

printf '\n\033[1m== %s\033[0m\n' "Bundle"
# --runtime-repo lets `flatpak install` fetch the GNOME runtime from
# Flathub when the user doesn't have it.
flatpak build-bundle \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  build/flatpak/repo "$file" "$app_id"
echo "Built $file ($(du -h "$file" | cut -f1))"

if $install; then
  flatpak install --user --noninteractive --reinstall "$file"
  echo "Installed. Run: flatpak run $app_id"
fi

#!/usr/bin/env bash
# Builds the AppImage inside the build image (Dockerfile). Called by
# tool/build_appimage.sh, never by hand:
#
#   build.sh <label> [flutter build flags...]
#
# The source is mounted read-only at /src and copied to /work, so nothing
# the build writes lands in the source folder (the host's own build/ stays
# valid). The AppImage goes to /out.
set -euo pipefail

label="$1"
shift
app_id=io.github.sharon_xa.cinemakom
file="cinemakom-${label}-linux-x64.AppImage"

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "Source"
rsync -a --delete \
  --exclude=/build --exclude=/dist --exclude=/coverage --exclude=/.git \
  --exclude=.dart_tool --exclude=/.fvm --exclude=/android --exclude=/windows \
  --exclude=/linux/flutter/ephemeral \
  /src/ /work/app/
cd /work/app

step "Flutter release bundle"
flutter pub get
flutter build linux --release "$@"
bundle=build/linux/x64/release/bundle

step "AppDir"
appdir=/work/AppDir
rm -rf "$appdir"
mkdir -p "$appdir/usr/lib" "$appdir/usr/bin" "$appdir/usr/share"
cp -a "$bundle" "$appdir/usr/lib/cinemakom"
ln -s ../lib/cinemakom/cinemakom "$appdir/usr/bin/cinemakom"
packaging=linux/packaging
install -Dm644 "$packaging/$app_id.desktop" -t "$appdir/usr/share/applications"
install -Dm644 "$packaging/$app_id.metainfo.xml" -t "$appdir/usr/share/metainfo"
mkdir -p "$appdir/usr/share/icons"
cp -r "$packaging/icons/hicolor" "$appdir/usr/share/icons/"
# What AppImage tools look for at the top.
cp "$packaging/$app_id.desktop" "$appdir/"
cp "$packaging/icons/hicolor/256x256/apps/$app_id.png" "$appdir/"
ln -s "$app_id.png" "$appdir/.DirIcon"
install -m755 linux/appimage/AppRun "$appdir/AppRun"
# The licenses of what we ship (GPL and LGPL ask for it).
mkdir -p "$appdir/usr/share/licenses"
cp -r /opt/deps/share/licenses/. "$appdir/usr/share/licenses/"
install -Dm644 LICENSE "$appdir/usr/share/licenses/cinemakom/LICENSE"

step "Libraries"
python3 linux/appimage/bundle_libs.py "$appdir/usr/lib/cinemakom"

step "AppImage"
mksquashfs "$appdir" /work/app.squashfs -root-owned -noappend \
  -comp zstd -Xcompression-level 19 -quiet
cat /opt/runtime-x86_64 /work/app.squashfs > "/out/$file"
chmod 755 "/out/$file"
rm /work/app.squashfs
# The files belong to whoever ran the build, not root.
chown "${HOST_UID:-0}:${HOST_GID:-0}" "/out/$file"
echo "Built $file ($(du -h "/out/$file" | cut -f1))"

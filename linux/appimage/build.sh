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
# Where AppImage updaters (AppImageUpdate, Gear Lever, AppImageLauncher)
# look for a newer version: the .zsync of the latest GitHub release, which
# says which blocks changed, so only those download. Written into the
# runtime's .upd_info section (1 KB, zero-filled), as appimagetool does.
update_info="gh-releases-zsync|sharon-xa|cinemakom|latest|cinemakom-*-linux-x64.AppImage.zsync"
cp /opt/runtime-x86_64 /work/runtime
python3 - /work/runtime "$update_info" <<'EOF'
import subprocess, sys
path, info = sys.argv[1], sys.argv[2].encode()
sections = subprocess.run(['readelf', '-SW', path], check=True,
                          capture_output=True, text=True).stdout
for line in sections.splitlines():
    f = line.replace('[', ' ').replace(']', ' ').split()
    if '.upd_info' in f:
        i = f.index('.upd_info')
        offset, size = int(f[i + 3], 16), int(f[i + 4], 16)
        break
else:
    sys.exit('the runtime has no .upd_info section')
if len(info) >= size:
    sys.exit('the update information is too long for .upd_info')
with open(path, 'r+b') as runtime:
    runtime.seek(offset)
    runtime.write(info.ljust(size, b'\0'))
EOF
cat /work/runtime /work/app.squashfs > "/out/$file"
chmod 755 "/out/$file"
rm /work/app.squashfs /work/runtime
# Made after the update information is in, from the final file. Its URL is
# relative: the AppImage sits next to it in the release.
(cd /out && zsyncmake -u "$file" -o "$file.zsync" "$file" >/dev/null)
# The files belong to whoever ran the build, not root.
chown "${HOST_UID:-0}:${HOST_GID:-0}" "/out/$file" "/out/$file.zsync"
echo "Built $file ($(du -h "/out/$file" | cut -f1)), and its .zsync"
echo "Updates from: $("/out/$file" --appimage-updateinformation)"

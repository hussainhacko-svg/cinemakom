#!/usr/bin/env python3
"""Copies into the AppImage every library the app needs that a Linux desktop
doesn't have (docs/PACKAGING.md §3). Runs in the build image (Dockerfile).

  bundle_libs.py <bundle>   # the Flutter bundle: <bundle>/cinemakom, lib/

Each library the app or a copied library asks for (its NEEDED entries) is:
  - already in <bundle>/lib: checked in turn;
  - in SYSTEM: left to the user's system, which has it wherever GTK 3 runs;
  - built by us (/opt/deps/lib): copied (libva into lib/libva: FALLBACK);
  - anything else stops the build, so nothing joins the AppImage, or is
    left out of it, without a decision here.
Copied libraries find each other next to themselves (RUNPATH $ORIGIN).
"""

import os
import shutil
import subprocess
import sys

DEPS = '/opt/deps/lib'

# On every desktop Linux the AppImage supports (glibc 2.35+, GTK 3). These
# must come from the system: glibc and the GPU drivers' libraries can't be
# bundled, and taking TLS, sound and fonts from the system means their
# security fixes reach us with system updates.
SYSTEM = {
    # glibc and the compiler's runtime
    'libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0', 'librt.so.1',
    'libresolv.so.2', 'libutil.so.1', 'libmvec.so.1', 'ld-linux-x86-64.so.2',
    'libstdc++.so.6', 'libgcc_s.so.1',
    # GTK 3 and what it is built on
    'libgtk-3.so.0', 'libgdk-3.so.0', 'libglib-2.0.so.0', 'libgobject-2.0.so.0',
    'libgio-2.0.so.0', 'libgmodule-2.0.so.0', 'libpango-1.0.so.0',
    'libpangocairo-1.0.so.0', 'libpangoft2-1.0.so.0', 'libcairo.so.2',
    'libcairo-gobject.so.2', 'libgdk_pixbuf-2.0.so.0', 'libatk-1.0.so.0',
    'libepoxy.so.0', 'libharfbuzz.so.0', 'libfontconfig.so.1',
    'libfreetype.so.6', 'libfribidi.so.0', 'libz.so.1', 'libX11.so.6',
    'libXi.so.6',
    # graphics: the drivers' own (Mesa, NVIDIA)
    'libEGL.so.1', 'libGL.so.1', 'libdrm.so.2',
    # sound and TLS (GnuTLS: its soname hasn't changed since 2015, while
    # OpenSSL 3 is already gone from Fedora 45's default install)
    'libasound.so.2', 'libpulse.so.0', 'libgnutls.so.30',
}

# Ours, but only for systems whose own is older or missing: they go in
# lib/libva, which nothing searches, and AppRun adds it when needed. The
# system's libva opens the system's VA-API drivers, and a driver built for a
# newer libva than ours (Mesa's, after the distro updates libva) won't open
# with ours: video would quietly decode on the CPU.
FALLBACK = {'libva.so.2', 'libva-drm.so.2'}
FALLBACK_DIR = 'libva'

# Asked for, but never loaded on desktop: jni's library (an Android plugin's
# dependency) needs Java's libjvm.so.
NEVER_LOADED = {'libjvm.so'}

# The Flutter engine and the compiled Dart code: left as they are.
UNTOUCHED = {'libflutter_linux_gtk.so', 'libapp.so'}


def needed(path):
    out = subprocess.run(['patchelf', '--print-needed', path],
                         check=True, capture_output=True, text=True).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def main():
    bundle = sys.argv[1]
    lib = os.path.join(bundle, 'lib')
    todo = [os.path.join(bundle, 'cinemakom')]
    todo += [os.path.join(lib, f) for f in sorted(os.listdir(lib))
             if '.so' in f and f not in UNTOUCHED]
    seen = set()
    copied = []
    unknown = {}
    while todo:
        path = todo.pop()
        if path in seen:
            continue
        seen.add(path)
        for name in needed(path):
            if name in SYSTEM or name in NEVER_LOADED:
                continue
            fallback = name in FALLBACK
            into = os.path.join(lib, FALLBACK_DIR) if fallback else lib
            here = os.path.join(into, name)
            if os.path.lexists(here):
                todo.append(here)
                continue
            ours = os.path.join(DEPS, name)
            if os.path.exists(ours):
                real = os.path.realpath(ours)
                os.makedirs(into, exist_ok=True)
                if fallback:
                    # Under its full name (libva.so.2.2400.0: VA-API 1.24),
                    # which AppRun compares with the system's.
                    dest = os.path.join(into, os.path.basename(real))
                    os.symlink(os.path.basename(real), here)
                else:
                    dest = here
                shutil.copy2(real, dest)
                os.chmod(dest, 0o755)
                subprocess.run(['strip', '--strip-unneeded', dest], check=True)
                copied.append(os.path.join(FALLBACK_DIR, name) if fallback
                              else name)
                todo.append(here)
                continue
            unknown.setdefault(name, set()).add(os.path.basename(path))
    if unknown:
        for name, by in sorted(unknown.items()):
            print(f'error: {name} (needed by {", ".join(sorted(by))}) is '
                  'neither ours nor in SYSTEM: decide in bundle_libs.py',
                  file=sys.stderr)
        sys.exit(1)
    # Plugins and copied libraries look for their dependencies next to
    # themselves. The app itself already does ($ORIGIN/lib).
    # libva-drm finds libva the same way, in lib/libva.
    for d in (lib, os.path.join(lib, FALLBACK_DIR)):
        for f in os.listdir(d) if os.path.isdir(d) else []:
            path = os.path.join(d, f)
            if ('.so' in f and f not in UNTOUCHED
                    and not os.path.islink(path)):
                subprocess.run(['patchelf', '--set-rpath', '$ORIGIN', path],
                               check=True)
    print('Bundled: ' + ', '.join(sorted(copied)))


if __name__ == '__main__':
    main()

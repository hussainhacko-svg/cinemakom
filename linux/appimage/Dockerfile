# The AppImage's build machine (docs/PACKAGING.md §3): Ubuntu 22.04, so the
# AppImage runs on any Linux with glibc 2.35 or newer. Used by
# tool/build_appimage.sh, here and in the release workflow.
#
# It builds what the AppImage carries (FFmpeg, libva, libass, libplacebo,
# libmpv) into /opt/deps, and has the pinned Flutter. Everything comes from
# a release archive checked against its sha256, or a git tag and commit.
#
# Keep the libraries current: an FFmpeg, mpv, libass, libplacebo or libva
# security release means a Cinemakom release.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git xz-utils bzip2 unzip file rsync patchelf \
      squashfs-tools python3 python3-pip \
      build-essential clang cmake ninja-build pkg-config nasm \
      libstdc++-12-dev libgtk-3-dev liblzma-dev libx11-dev libxi-dev \
      libdrm-dev libgnutls28-dev zlib1g-dev libasound2-dev libpulse-dev \
      libfreetype-dev libfribidi-dev libharfbuzz-dev libfontconfig-dev \
      libegl-dev libgl-dev \
    && rm -rf /var/lib/apt/lists/*
# mpv needs a newer meson than 22.04's.
RUN pip3 install --no-cache-dir meson==1.12.1

ENV PREFIX=/opt/deps
ENV PKG_CONFIG_PATH=/opt/deps/lib/pkgconfig \
    LD_LIBRARY_PATH=/opt/deps/lib \
    CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2" \
    CXXFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2"
WORKDIR /tmp/src

# fetch <url> <sha256>: downloads and unpacks into the current folder.
# lic <name> <files>: keeps a library's license, shipped in the AppImage.
RUN printf '%s\n' '#!/bin/sh' 'set -eu' \
      'f=$(basename "$1"); curl -fsSL -o "$f" "$1"' \
      'echo "$2  $f" | sha256sum -c -' \
      'tar xf "$f" && rm "$f"' > /usr/local/bin/fetch \
    && printf '%s\n' '#!/bin/sh' 'set -eu' \
      'd=$PREFIX/share/licenses/$1; shift; mkdir -p "$d"; cp "$@" "$d"/' \
      > /usr/local/bin/lic \
    && chmod +x /usr/local/bin/fetch /usr/local/bin/lic

# libva: our own, current, so the system's newest VA-API drivers load (an
# older libva can't load a driver built for a newer one). Drivers stay the
# system's: the path covers Debian/Ubuntu, Fedora/openSUSE, Arch and NixOS.
RUN fetch https://github.com/intel/libva/releases/download/2.24.1/libva-2.24.1.tar.bz2 \
      eec6050b52876f229bd35e9df17cd31a06785e18e6f7990c445b584628483d67 \
    && meson setup libva-build libva-2.24.1 --prefix=$PREFIX --libdir=lib \
      --buildtype=release -Dwith_x11=no -Dwith_wayland=no -Dwith_glx=no \
      -Ddriverdir=/usr/lib/x86_64-linux-gnu/dri:/usr/lib64/dri:/usr/lib/dri:/run/opengl-driver/lib/dri \
    && ninja -C libva-build install \
    && lic libva libva-2.24.1/COPYING && rm -rf /tmp/src/*

# NVIDIA's decoder headers: FFmpeg loads the driver's libraries at run time,
# so nothing of NVIDIA's is linked or shipped. 12.1 needs driver 530+.
RUN fetch https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.1.14.1/nv-codec-headers-12.1.14.1.tar.gz \
      043e46265517855f13bcb98b3a225b2761b2a83983b1645fa1d05876f1c3a781 \
    && make -C nv-codec-headers-12.1.14.1 install PREFIX=$PREFIX \
    && rm -rf /tmp/src/*

# FFmpeg: only what playback needs (decoders, demuxers, protocols, filters).
# TLS comes from the system's GnuTLS, so its fixes reach us with system
# updates. (Not OpenSSL: Fedora 45 moved to OpenSSL 4, and a library linked
# to OpenSSL 3 doesn't load there.) LGPL 2.1; mpv makes the whole GPL.
# --disable-autodetect: nothing joins by accident.
RUN fetch https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz \
      7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3 \
    && cd ffmpeg-8.1.3 && ./configure --prefix=$PREFIX \
      --enable-shared --disable-static --disable-programs --disable-doc \
      --disable-debug --enable-pic \
      --disable-autodetect --enable-iconv --enable-zlib --enable-gnutls \
      --enable-libdrm --enable-vaapi \
      --enable-ffnvcodec --enable-cuda --enable-cuvid --enable-nvdec \
      --disable-encoders --enable-encoder=png,mjpeg \
      --disable-muxers --disable-indevs --disable-outdevs \
    && make -j"$(nproc)" && make install \
    && lic ffmpeg LICENSE.md COPYING.LGPLv2.1 \
    && rm -rf /tmp/src/*

RUN fetch https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz \
      2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc \
    && cd libass-0.17.5 && ./configure --prefix=$PREFIX --disable-static \
      --disable-libunibreak \
    && make -j"$(nproc)" && make install && lic libass COPYING \
    && rm -rf /tmp/src/*

# Git, not a tarball: the build needs its submodules (glad, jinja,
# fast_float). mpv renders through OpenGL here (media_kit), so no Vulkan.
RUN git clone --depth 1 --branch v7.387.0 --recurse-submodules --shallow-submodules \
      https://code.videolan.org/videolan/libplacebo.git \
    && test "$(git -C libplacebo rev-parse HEAD)" = 275f7dea27924cdd34ab2e6c20e448b6bc4fab65 \
    && meson setup placebo-build libplacebo --prefix=$PREFIX --libdir=lib \
      --buildtype=release -Dauto_features=disabled -Dopengl=enabled \
      -Ddovi=enabled -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
    && ninja -C placebo-build install \
    && lic libplacebo libplacebo/LICENSE && rm -rf /tmp/src/*

# Only libmpv (libmpv.so.2), what media_kit loads. No X11 or Wayland code:
# the app draws the window and gives mpv an OpenGL context (plain-gl), and
# mpv 0.42's Wayland code needs a newer libwayland than 22.04's. Hardware
# decoding: NVIDIA without copies (CUDA), VA-API (Intel, AMD) by copying
# frames back (vaapi-copy, through FFmpeg: mpv's own VA-API code needs its
# X11 or Wayland code).
RUN fetch https://github.com/mpv-player/mpv/archive/refs/tags/v0.42.0.tar.gz \
      bcfebbfa2b65a6d88dc97ea18117831072373e38b5785a2afb874ed4df5070dd \
    && meson setup mpv-build mpv-0.42.0 --prefix=$PREFIX --libdir=lib \
      --buildtype=release -Dauto_features=disabled \
      -Dlibmpv=true -Dcplayer=false -Dbuild-date=false -Dlua=disabled \
      -Dgl=enabled -Dplain-gl=enabled -Dlibavdevice=enabled \
      -Diconv=enabled -Dzlib=enabled -Dpulse=enabled -Dalsa=enabled \
      -Dcuda-hwaccel=enabled -Dcuda-interop=enabled \
    && ninja -C mpv-build install \
    && lic mpv mpv-0.42.0/LICENSE.GPL mpv-0.42.0/LICENSE.LGPL mpv-0.42.0/Copyright && rm -rf /tmp/src/*

# The AppImage runtime: the small program at the start of the file that
# mounts it. This one is static, so it doesn't need the system's libfuse2.
# Upstream only publishes "continuous": when the checksum stops matching,
# look at what changed there before taking the new one.
RUN curl -fsSL -o /opt/runtime-x86_64 \
      https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64 \
    && echo "617aa77314d57c8b8e4fae9c3f0b35af7b30d5529cb69e98f64f92510ed98a46  /opt/runtime-x86_64" \
      | sha256sum -c -

# Flutter, the version in .fvmrc (tool/build_appimage.sh passes it).
ARG FLUTTER_VERSION
RUN test -n "$FLUTTER_VERSION" \
    && curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
      | tar xJ -C /opt \
    && git config --global --add safe.directory '*' \
    && /opt/flutter/bin/flutter config --no-analytics --no-cli-animations \
    && /opt/flutter/bin/flutter precache --linux --no-android --no-ios \
    && /opt/flutter/bin/flutter --version
ENV PATH=/opt/flutter/bin:$PATH

WORKDIR /work

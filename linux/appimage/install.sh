#!/usr/bin/env bash
# Installs Cinemakom on Linux, for this user only (no sudo), or updates it:
#
#   curl -fsSL https://github.com/sharon-xa/cinemakom/releases/latest/download/install.sh | bash
#
#   install.sh                       # the latest release (again: updates it)
#   install.sh --version v1.2.0      # a given release
#   install.sh --file <x.AppImage>   # an AppImage already downloaded
#   install.sh --uninstall           # removes the app; your library stays
#
# It downloads the release's AppImage, checks it against the release's
# SHA256SUMS.txt, and unpacks it into ~/.local/lib/cinemakom, so it runs
# without FUSE. Then it adds `cinemakom` to ~/.local/bin and Cinemakom to
# the applications menu. docs/PACKAGING.md §3.
set -euo pipefail

repo=sharon-xa/cinemakom
app_id=io.github.sharon_xa.cinemakom
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
[[ "$data_home" = /* ]] || data_home="$HOME/.local/share"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
[[ "$cache_home" = /* ]] || cache_home="$HOME/.cache"
dest="$HOME/.local/lib/cinemakom"
bin="$HOME/.local/bin/cinemakom"
desktop="$data_home/applications/$app_id.desktop"
icons="$data_home/icons/hicolor"

say() { printf '%s\n' "$*"; }
die() { printf 'cinemakom: %s\n' "$*" >&2; exit 1; }

# Not read from $0: piped into bash, there's no file.
usage() {
  cat <<'EOF'
Installs or updates Cinemakom for this user (no sudo):
  install.sh                       the latest release (again: updates it)
  install.sh --version v1.2.0      a given release
  install.sh --file <x.AppImage>   an AppImage already downloaded
  install.sh --force               installs again, even the same version
  install.sh --uninstall           removes the app; your library stays
EOF
}

uninstall() {
  [[ -d "$dest" ]] || die "Cinemakom isn't installed (no $dest)."
  # The icons it installed: the same names as in the app's own copy.
  (cd "$dest/usr/share/icons/hicolor" && find . -type f) | while read -r f; do
    rm -f "$icons/$f"
  done
  [[ "$(readlink "$bin" 2>/dev/null)" == "$dest/"* ]] && rm -f "$bin"
  rm -f "$desktop"
  rm -rf "$dest"
  refresh_menus
  say "Cinemakom is uninstalled."
  say "Your library, settings and downloads are still there. To remove them too:"
  say "  ${XDG_DATA_HOME:-~/.local/share}/$app_id     (library, settings)"
  say "  ${XDG_CACHE_HOME:-~/.cache}/$app_id     (posters)"
  say "  ${XDG_STATE_HOME:-~/.local/state}/$app_id     (activity log)"
  say "  your Videos folder's Cinemakom folder     (downloads)"
}

refresh_menus() {
  command -v update-desktop-database >/dev/null &&
    update-desktop-database -q "$data_home/applications" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null && [[ -f "$icons/index.theme" ]] &&
    gtk-update-icon-cache -q -t "$icons" 2>/dev/null || true
}

latest_tag() {
  # /releases/latest redirects to /releases/tag/<tag>: no API, no token.
  local url
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$repo/releases/latest") ||
    die "Couldn't reach GitHub. Check your connection and try again."
  [[ "$url" == */tag/* ]] || die "No release found at github.com/$repo."
  printf '%s' "${url##*/}"
}

main() {
  local version="" file="" force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) version="${2:?--version needs a tag, such as v1.2.0}"; shift 2 ;;
      --file) file="${2:?--file needs an AppImage}"; shift 2 ;;
      --force) force=true; shift ;;
      --uninstall) uninstall; return ;;
      -h|--help) usage; return ;;
      *) die "unknown option $1 (try --help)" ;;
    esac
  done

  [[ "$(uname -s)" == Linux ]] || die "this installs the Linux app."
  [[ "$(uname -m)" == x86_64 ]] || die "only x86_64 (64-bit PC) is supported."
  [[ -n "$version" && -n "$file" ]] && die "use --version or --file, not both."

  mkdir -p "$cache_home"
  # In the cache, not /tmp: the AppImage runs to unpack itself, and /tmp is
  # mounted noexec on some systems. Global, so the EXIT trap still sees it.
  tmp=$(mktemp -d "$cache_home/cinemakom-install.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT

  local appimage="$tmp/cinemakom.AppImage" label
  if [[ -n "$file" ]]; then
    [[ -f "$file" ]] || die "no such file: $file"
    cp "$file" "$appimage"
    label="$(basename "$file")"
  else
    command -v curl >/dev/null || die "curl is needed: install it, then run this again."
    [[ -n "$version" ]] || version=$(latest_tag)
    label="$version"
    if [[ -f "$dest/VERSION" && "$(cat "$dest/VERSION")" == "$version" ]] && ! $force; then
      say "Cinemakom $version is already installed (--force installs it again)."
      return
    fi
    local name="cinemakom-$version-linux-x64.AppImage"
    local base="https://github.com/$repo/releases/download/$version"
    say "Downloading Cinemakom $version…"
    curl -fL --progress-bar -o "$appimage" "$base/$name" ||
      die "couldn't download $name (is $version a release with a Linux AppImage?)"
    curl -fsSL -o "$tmp/SHA256SUMS.txt" "$base/SHA256SUMS.txt" ||
      die "couldn't download the release's SHA256SUMS.txt"
    local want
    want=$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1 }' "$tmp/SHA256SUMS.txt")
    [[ -n "$want" ]] || die "$name isn't in the release's SHA256SUMS.txt"
    [[ "$(sha256sum "$appimage" | cut -d' ' -f1)" == "$want" ]] ||
      die "the download is damaged (its checksum doesn't match). Try again."
  fi

  say "Installing…"
  chmod +x "$appimage"
  (cd "$tmp" && ./cinemakom.AppImage --appimage-extract >/dev/null) ||
    die "couldn't unpack the AppImage"
  [[ -x "$tmp/squashfs-root/AppRun" ]] || die "that file isn't a Cinemakom AppImage"
  printf '%s\n' "$label" > "$tmp/squashfs-root/VERSION"

  # Swap the old version out only once the new one is complete. A running
  # Cinemakom keeps working until it's closed.
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest.new" "$dest.old"
  mv "$tmp/squashfs-root" "$dest.new"
  [[ -d "$dest" ]] && mv "$dest" "$dest.old"
  mv "$dest.new" "$dest"
  rm -rf "$dest.old"

  mkdir -p "$(dirname "$bin")" "$(dirname "$desktop")" "$icons"
  ln -sfn "$dest/AppRun" "$bin"
  cp -r "$dest/usr/share/icons/hicolor/." "$icons/"
  # The menu entry runs the app by its full path: ~/.local/bin isn't on
  # every desktop's PATH.
  sed -e "s|^Exec=.*|Exec=$dest/AppRun|" -e "/^TryExec=/d" \
    -e "/^Exec=/a TryExec=$dest/AppRun" \
    "$dest/usr/share/applications/$app_id.desktop" > "$desktop"
  refresh_menus

  say "Cinemakom $label is installed. Open it from your applications menu."
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) say "Or run: cinemakom" ;;
    *) say "Or run: $bin" ;;
  esac
  say "To update later, run this again."
}

main "$@"

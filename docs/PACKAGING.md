# Packaging for Linux and Windows

The plan for shipping Cinemakom on desktop (2026-11-24): where the app keeps
its files, which packages to make, and in what order. Android is an APK and
isn't covered here. PLAN.md Phase 8 ("Packaging") points to this file.

Milestones are P0–P5 (§5). Decisions for the owner are in §6.

---

## 1. Where the app keeps its files today

Checked on 2026-11-24 in the packages' sources and on the development
machine (Arch, `/tmp` on tmpfs). The app ID is `io.github.sharon_xa.cinemakom`.
On Windows, path_provider names folders `io.github.sharon_xa\Cinemakom`
(CompanyName and ProductName in `windows/runner/Runner.rc`).

| What | Linux now | Windows now | Problem |
|---|---|---|---|
| Library database (`cinemakom.sqlite`: history, favorites, downloads list) | `~/Documents/` | `Documents\` | drift_flutter's default is `getApplicationDocumentsDirectory`. It's the user's own folder, it's often synced to OneDrive on Windows, and **inside a Flatpak it isn't writable at all** |
| Image cache (posters) | `/tmp/libCachedImageData` | `%TEMP%` | flutter_cache_manager's default. On tmpfs it uses RAM and is gone at every reboot, while its index (in the data folder) still lists the files |
| Settings (`shared_preferences.json`) | `~/.local/share/<id>/` | `%APPDATA%\…` (Roaming) | Fine. XDG's place for settings is `~/.config`, but moving them needs a custom store (§6) |
| Download engine state, kept resume data | `~/.local/share/<id>/` | Roaming | Fine on Linux. On Windows it belongs in Local: it's machine-specific |
| Activity log (`logs/`) | `~/.local/share/<id>/logs` | Roaming | XDG puts logs in `$XDG_STATE_HOME` (`~/.local/state`). Windows: Local |
| Subtitle fonts (`libass-fonts/`, copied from assets) | data folder | Roaming | Can be rebuilt any time: belongs in the cache |
| Default download folder | `~/Videos/Cinemakom`, hard-coded | `%USERPROFILE%\Videos\Cinemakom` | Linux ignores `XDG_VIDEOS_DIR`, which is translated on many systems (`~/Vidéos`, `~/الفيديو`) or moved. Windows ignores the Videos known folder, which users move to OneDrive or another drive |
| Unfinished downloads | `<download folder>/.partial` | same | Hidden on Linux. On Windows a dot doesn't hide it, so the folder shows up in Videos |
| Activity log export | temp folder | temp folder | Fine |

The machine also has a stale `~/.local/share/<id>/fonts/` from an early
build.

### Should we follow XDG? Yes

- **Users expect it.** Backups and dotfile sync cover `~/.local/share` and
  `~/.config`. Cleaners empty `~/.cache` and `/tmp`. An app that drops a
  database in `~/Documents` looks broken or rude.
- **Flatpak depends on it.** Inside the sandbox the XDG variables point into
  `~/.var/app/<id>/`, so an app that follows XDG needs no special case there.
  `~/Documents` isn't reachable without an extra permission, so the
  database wouldn't open.
- **Windows has the same split:** Roaming for small settings, Local for
  machine-specific data and caches, the Videos known folder for videos.

## 2. P0: put every file in the right place (before any package)

One small module, `lib/core/platform/app_dirs.dart`, decides every folder.
Nothing else calls path_provider for these.

| Folder | Linux | Windows | Android (unchanged) |
|---|---|---|---|
| data (database, engine state) | `$XDG_DATA_HOME/<id>` (`~/.local/share/…`) | `%LOCALAPPDATA%\io.github.sharon_xa\Cinemakom` | app support folder |
| cache (posters, subtitle fonts) | `$XDG_CACHE_HOME/<id>` (`~/.cache/…`) | `%LOCALAPPDATA%\…\cache` | app cache folder |
| state (logs) | `$XDG_STATE_HOME/<id>` (`~/.local/state/…`) | `%LOCALAPPDATA%\…\logs` | external app folder (for `adb pull`), as now |
| default downloads | `$(xdg-user-dir VIDEOS)/Cinemakom` | Videos known folder `\Cinemakom` | as now |
| settings | unchanged (shared_preferences picks it) | unchanged | unchanged |

Following the XDG spec: an unset, empty or relative variable falls back to
the default (`~/.local/share`, `~/.cache`, `~/.local/state`). The
`xdg_directories` package (already in the tree, through path_provider_linux)
reads these and `user-dirs.dirs`.

Work:
- **Database:** `driftDatabase(name: 'cinemakom', native:
  DriftNativeOptions(databaseDirectory: …))`.
- **Image cache:** one `CacheManager(Config(…, fileSystem: IOFileSystem(<cache>/images)))`
  passed to `MediaImage`, with the index kept next to it.
- **Logs and subtitle fonts:** `logDirectory()` uses state, `subtitle_fonts.dart`
  uses cache.
- **Default download folder:** `defaultDesktopFolder()` asks the OS. A folder
  the user picked in Settings is kept as is.
- **Windows:** set the hidden attribute on `.partial`.
- **Migration, once, on startup:** move `cinemakom.sqlite` from Documents
  (and its `-wal`, `-shm` and `-journal` files, if any) when the new
  location is empty. Never overwrite. Then delete the old `libass-fonts/`
  and `fonts/` folders and the stale cache index. If anything fails, log it
  and keep the old file where it is. Losing the library is the one thing
  this must never do.
- **Tests:** `AppDirs` resolves from an environment map, so the XDG rules
  (unset, empty, relative, `user-dirs.dirs` with `$HOME/…` and translated
  names) are unit tests. The migration is tested on a temp folder: moved,
  kept when the target exists, a failure keeps the old file.
- **Docs:** this table goes into the AGENTS.md rules ("files go through
  `AppDirs`").

## 3. Linux

### What limits a plain binary (checked 2026-11-24)
- **libmpv 2 is a hard dependency.** `libmedia_kit_video_plugin.so` links
  `libmpv.so.2`, so the app doesn't start on systems that only have
  libmpv 1 (Ubuntu 22.04, Debian 11). The README's "Older Debian and
  Ubuntu: `libmpv1`" row is wrong and should go.
- **glibc:** a binary needs a glibc at least as new as the one on the
  machine that built it. The local build needs GLIBC_2.38. CI builds on
  `ubuntu-latest`, which moves to new Ubuntu versions by itself.
- GTK 3 and the codecs come from the user's system, so behaviour varies
  between distros.

### What we ship and what comes from the system
Bundling the player's libraries makes the app work the same everywhere,
but their security fixes become ours. FFmpeg parses whatever file the CDN
sends. A distro patches its own copy; ours stays as old as our last
release. So:

- **Bundled:** libmpv and what it brings (FFmpeg, libass, libplacebo), in
  the Flatpak, the tarball and on Windows. **Rule: an FFmpeg or mpv
  security release means a Cinemakom release.** CI can warn us: Flathub's
  update checker for the Flatpak modules, and a scheduled job comparing
  our versions with the latest.
- **Never bundled:** glibc (a binary needs at least the build machine's),
  GPU drivers (Mesa or NVIDIA, libGL and EGL, VA-API drivers: they must
  match the kernel and GPU), and GTK where possible (themes, input
  methods for Arabic keyboards, Wayland). In the Flatpak, Flathub's
  runtime provides and patches these.
- **Licences:** mpv and FFmpeg are GPL or LGPL, and the app is MIT, which
  is compatible. Each package includes their licence texts and links to
  the exact sources we built.
- **AUR:** uses the system mpv. That's Arch's convention, and Arch's copy
  is always current.

### Formats, in order

1. **Flatpak (the main package).** It brings its own runtime (glibc, GTK)
   and our libmpv and FFmpeg, so one build runs the same on every distro.
   It's sandboxed, updates through GNOME Software and KDE Discover, and
   Flathub is where Linux users look first.
   - **Manifest** `linux/flatpak/io.github.sharon_xa.cinemakom.yml`:
     - Runtime: the GNOME Platform, which includes GTK 3.
     - Modules: libmpv and its libraries (libass, libplacebo, FFmpeg) built
       from source, as other mpv-based apps on Flathub do.
     - The app: the Flutter release bundle.
   - **Permissions:**
     - `--share=network`, `--share=ipc`
     - `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`
     - `--socket=pulseaudio`
     - `--filesystem=xdg-videos`, for downloads
     - Other folders, and Save a copy of the log, go through the file
       chooser portal.
     - Keeping the screen on already uses the Inhibit portal
       (wakelock_plus), so it needs no permission.
   - **AppStream metainfo** `io.github.sharon_xa.cinemakom.metainfo.xml`:
     the description in English and Arabic, screenshots (from
     `integration_test/screenshots_test.dart`), release notes and the
     required OARS content declaration. That declaration describes the app
     for the store; it isn't a ratings feature.
   - **First** attach a `.flatpak` bundle to each GitHub release, built in
     CI. **Then** submit to Flathub. Flathub reviews apps and prefers
     source builds: check its current rules for Flutter apps when
     submitting. The app ID already matches the `io.github.<user>` form
     Flathub verifies through GitHub.
2. **AUR `cinemakom-bin` (Arch, Manjaro).** A PKGBUILD that installs the
   release tarball in `/opt/cinemakom`, a launcher in `/usr/bin`, the
   desktop file, the icons and the metainfo. `depends=(mpv gtk3)`. Small,
   and Arch users expect it.
3. **The tarball, done properly** (for everyone else):
   - Add `install.sh` and `uninstall.sh` that do what the README asks
     people to type: a per-user install into `~/.local`, a symlink in
     `~/.local/bin`, the desktop file, icons and metainfo.
   - Bundle libmpv and FFmpeg in `lib/`, built in CI from pinned sources,
     so nothing has to be installed first. The launcher sets the library
     path to the bundle's `lib/`.
   - Build on `ubuntu-22.04`, not `ubuntu-latest`: a runner that jumps
     ahead silently raises the glibc the app needs. That makes 2022 or
     newer distros the requirement.
   - Write the real requirements in the README: GTK 3 and a 2022 or newer
     distro. Drop the "install libmpv" table.
4. **Later, if people ask:** a `.deb` (Debian, Ubuntu) and an `.rpm`
   (Fedora, where mpv comes from RPM Fusion). Flatpak covers both today.
5. **Not planned:**
   - **AppImage:** we would have to bundle libmpv, FFmpeg and GTK, glibc
     would still tie it to old build machines, and it doesn't update.
     Flatpak covers the same "one file for every distro" need better.
   - **Snap:** Flatpak covers the same users.

### Desktop integration (what makes it feel native)
- Done: desktop file with an Arabic name, `StartupWMClass` matching the app
  ID, icons at every size plus SVG.
- **One instance:** the runner uses `G_APPLICATION_NON_UNIQUE`, so a second
  launch starts a second process with its own download engine, writing to
  the same database. It also renames the first one's `current.log`. Make
  the app unique, so a second launch brings the open window to the front.
  On Windows, do the same with a named mutex in `main.cpp`.
- **Metainfo:** GNOME Software and Discover show apps from it (Flatpak
  item above).
- **To check on GNOME and KDE, Wayland and X11:** full screen in the
  player, fractional scaling, the screen staying on during playback, and
  hardware decoding (VA-API) with Intel, AMD and NVIDIA.
- **Optional feature:** MPRIS, so media keys, headset buttons and the
  desktop's media controls work with the player.

## 4. Windows

### What's missing today
- **The Visual C++ runtime isn't shipped.** The zip has no `msvcp140.dll`,
  `vcruntime140.dll` or `vcruntime140_1.dll`. On a PC without the
  "Microsoft Visual C++ Redistributable", the app won't start ("VCRUNTIME140_1.dll
  was not found"). Flutter's docs say to ship them next to the `.exe`:
  copy them in `windows/CMakeLists.txt`'s install step.
- **Never run on a real Windows machine** (README). The new CI job runs the
  tests there but doesn't open the app.
- **libmpv is from 2023-09-24.** `media_kit_libs_windows_video` downloads
  that fixed build, with the FFmpeg of its time, so the bundled player is
  three years behind on security fixes. Move to a current build (a newer
  media_kit package, or our own build of libmpv in CI) and follow the
  §3 rule from then on.
- **Unsigned:** Windows SmartScreen warns ("Windows protected your PC") the
  first time a downloaded `.exe` or installer runs.

### Formats, in order
1. **An installer (Inno Setup), per user, no admin rights:**
   - Installs in `%LOCALAPPDATA%\Programs\Cinemakom`.
   - Start menu shortcut, and a desktop one if the user wants it.
   - An entry in Installed apps, with an uninstaller.
   - Installs over the last version (a fixed AppId) and closes a running
     Cinemakom first.
   - English and Arabic setup screens.
   - On uninstall, asks before removing the library and settings. Never
     deletes downloaded videos: those belong to the user.
   - Built in the release workflow on `windows-latest`, which installs
     Inno Setup first.
2. **The portable zip, kept**, with the runtime DLLs, for people who don't
   want an installer.
3. **winget:** a manifest in `microsoft/winget-pkgs` pointing at the
   installer, so `winget install Cinemakom` works and updates. The release
   workflow can update it (`wingetcreate`).
4. **Code signing**, to stop the SmartScreen warning: apply to SignPath
   Foundation (free signing for open-source projects), or Azure Trusted
   Signing (paid monthly, identity checks, not offered everywhere). Not
   needed to ship, but it's the main thing that makes Windows users trust
   a download.
5. **Later:** MSIX and the Microsoft Store (updates, and Microsoft signs
   it). MSIX redirects writes to AppData and limits the file system, so the
   downloads engine and the folder picker need checking there first.

### Testing on Windows
- **CI** (`windows-latest`) runs the tests, plus a smoke test in the
  release workflow: install silently, start the app, check it's still
  running after a few seconds, uninstall. CI runners already have the
  Visual C++ runtime, so CI can't catch a missing DLL.
- **Windows Sandbox on the owner's Windows machine** (Windows 10 and 11
  Pro, virtualization on) is a clean, throwaway Windows: no Visual C++
  runtime, nothing installed. Use it for every installer check: a first
  install, an update over the last version, uninstall, a zip started from
  Downloads, SmartScreen. Closing it erases everything, so each run starts
  clean. On Windows Home, use a Windows 11 evaluation VM on the Linux
  machine (KVM) instead.
- **The owner's Windows machine itself**, on real hardware: playback up to
  4K with hardware decoding, full screen, 150% and 200% scaling, Arabic
  keyboard input, a Videos folder moved to OneDrive or another drive,
  downloads, and the Activity log.

## 5. Milestones

| | What | Done when |
|---|---|---|
| **P0** | Folders (§2), migration, one instance on both OSs | Tests green. On this machine the library moves out of `~/Documents` with nothing lost, posters survive a reboot, logs are in `~/.local/state` |
| **P1** | Windows: runtime DLLs, a current libmpv, first real-machine run, Inno installer in CI | In Windows Sandbox: installs, starts, updates over itself and uninstalls cleanly. On the owner's machine: plays up to 4K and downloads |
| **P2** | Linux: metainfo, Flatpak bundle in CI, tarball with libmpv bundled and `install.sh`, built on `ubuntu-22.04`, README fixed | The `.flatpak` installs and plays on Fedora, Ubuntu 24.04 and Arch, in GNOME and KDE. The tarball plays on Ubuntu 22.04 with no mpv installed |
| **P3** | AUR `cinemakom-bin` | `yay -S cinemakom-bin` works |
| **P4** | Flathub and winget | Listed, and updates arrive by themselves |
| **P5** | Signing (SignPath), MPRIS, update notice (§6) | As decided |

## 6. Decisions for the owner

1. **Publishing on Flathub and winget:** both are public listings with a
   review. OK to submit once P2 and P1 are done?
2. **"Update available" for the zip, tarball and installer:** these don't
   update themselves. A check against GitHub Releases would be a
   third-party call, and AGENTS.md allows only the status page. Allow this
   one exception, or rely on Flathub, AUR and winget for updates?
3. **Settings in `~/.config`:** strict XDG, but it needs our own settings
   file instead of shared_preferences on Linux. Recommendation: not worth
   it now. Every other file moves in P0.
4. **Code signing:** apply to SignPath Foundation? It needs the project's
   public repository and a short application.
5. **Windows installer:** per user (recommended: no admin, installs over
   itself quietly) or for all users?

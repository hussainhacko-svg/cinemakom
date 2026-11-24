# Packaging for Linux and Windows

The plan for shipping Cinemakom on desktop (2026-11-24): where the app keeps
its files, which packages to make, and in what order. Android is an APK and
isn't covered here. PLAN.md Phase 8 ("Packaging") points to this file.

Milestones are P0–P4 (§5). Decisions for the owner are in §6.

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

*Built 2026-11-24. Checked on Linux, on the owner's real library: it
moved out of `~/Documents` with its history intact, the log moved to
`~/.local/state`, posters fill `~/.cache`, the old files went, and a
second launch hands over to the open window. Windows is left to check:
§2.1.*

`AppDirs` (`lib/core/platform/app_dirs.dart`) decides the app's own
folders on desktop, once, before `runApp`. On Android and in tests
`AppDirs.current` is `null` and every file stays where it always was
(moving Android's database would lose people's libraries).

| Folder | Linux | Windows | Android |
|---|---|---|---|
| data (library database) | `$XDG_DATA_HOME/<id>` (`~/.local/share/…`) | `%LOCALAPPDATA%\io.github.sharon_xa\Cinemakom` | unchanged |
| cache (posters, subtitle font) | `$XDG_CACHE_HOME/<id>` (`~/.cache/…`) | `…\Cinemakom\cache` (Local) | unchanged |
| state (`logs/`) | `$XDG_STATE_HOME/<id>` (`~/.local/state/…`) | `…\Cinemakom\logs` (Local) | unchanged (external folder, for `adb pull`) |
| default downloads | `XDG_VIDEOS_DIR/Cinemakom` | Videos known folder `\Cinemakom` | unchanged |
| settings, download engine state | `~/.local/share/<id>` (the packages' own choice) | Roaming AppData (the packages' own choice) | unchanged |

The last row can't move: shared_preferences and background_downloader
pick the app support folder themselves. On Linux that's already the XDG
data folder. On Windows it's Roaming, which works; it only matters on
company networks that sync Roaming between PCs.

XDG rules followed (and unit-tested, `test/core/platform/app_dirs_test.dart`):
an unset, empty or relative variable falls back to the default; the
videos folder comes from `user-dirs.dirs` (`$HOME/…`, translated names,
absolute paths), else `XDG_VIDEOS_DIR`, else `~/Videos`; a value of just
`$HOME` means the folder is turned off.

What changed:
- **Database:** `appDatabaseDirectory` (`lib/core/storage/legacy_files.dart`)
  is drift's `databaseDirectory`. On desktop it first moves an old
  `cinemakom.sqlite` (and any `-journal`, `-wal`, `-shm`) from Documents:
  copied first, switched into place when every copy is written (the
  database last), and the old files deleted only then. A library already
  in the new folder is never overwritten; a failed copy keeps the old
  files and is logged. A start that stops halfway finishes on the next.
- **Posters:** one cache, `appImageCache` (`lib/core/storage/image_cache.dart`),
  for `MediaImage`, `TvImage` and the seek preview, files and index in
  `<cache>/images`.
- **Logs:** `logDirectory()` uses `<state>/logs`; the old log moves there
  before the log opens its file, so the last session's survives.
- **Subtitle font:** `<cache>/subtitle-fonts`.
- **Downloads:** `defaultDesktopFolder()` uses the videos folder. A folder
  picked in Settings is kept. On Windows the `.partial` folder gets the
  hidden attribute.
- **Cleanup, in the background:** the old `libass-fonts/` and `fonts/`
  (only if it holds nothing but fonts), the old cache index and the old
  poster files in the temp folder.
- **One instance, in release builds:** Linux is a unique `GApplication`
  (a second launch presents the open window); Windows takes a named mutex
  and brings the open window forward. Debug builds stay non-unique, so
  `flutter run` and the integration tests start while the installed app
  is open.

### 2.1 Left to check on Windows

The Windows code compiles only on Windows, and `main.cpp`'s change has
never been built. Get a build either way:
- **From CI (no tools needed):** run the Release workflow by hand
  (Actions → Release → Run workflow, version `v0.0.0-dev`; it publishes
  nothing), then download the `release-windows` artifact and unzip it.
- **On the Windows machine:** Flutter 3.47.9 through fvm, Visual Studio
  2022 with "Desktop development with C++", then
  `fvm flutter build windows --release`; the app is in
  `build\windows\x64\runner\Release`.

Steps (about 15 minutes):
1. **An old library to move.** Unzip an earlier release (v1.0.x from
   GitHub), start it, play any title for a few seconds and add one to
   your list, then close it. `Documents\cinemakom.sqlite` now exists.
2. **Start the new build.** Continue watching and My list show what you
   did in step 1.
3. **Files:**
   - `Documents\cinemakom.sqlite` is gone.
   - `%LOCALAPPDATA%\io.github.sharon_xa\Cinemakom\` has
     `cinemakom.sqlite`, `logs\current.log` and `cache\images\` (filling as
     posters show).
   - `%APPDATA%\io.github.sharon_xa\Cinemakom\` still has the settings
     and the download engine's folders (expected, see above).
4. **Activity log** (Settings → Help): the first lines say
   `folders: data … · videos …` and `moved the library from …`. Save a
   copy works.
5. **Downloads:** Settings shows `<your Videos folder>\Cinemakom`; if
   Videos is moved (OneDrive, another drive), the moved one. Start a
   download: `Cinemakom\.partial` only shows in Explorer with hidden
   items turned on.
6. **One instance:** with the app open, start `cinemakom.exe` again. No
   second window opens; the open one comes to the front, also when it was
   minimized.
7. If anything is off, Settings → Help → Activity log → Save a copy, and
   send the file.

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

- **Bundled:** libmpv, libass and libplacebo in the Flatpak; libmpv with
  its FFmpeg on Windows. **Rule: a security release of any of them means
  a Cinemakom release.** CI can warn us: Flathub's update checker for the
  Flatpak modules, and a scheduled job comparing our versions with the
  latest.
- **FFmpeg in the Flatpak comes from the runtime** (GNOME 51: FFmpeg 8.1,
  with H.264 and the other patented codecs through
  `org.freedesktop.Platform.codecs-extra`), so its security fixes arrive
  with runtime updates, not with ours. FFmpeg is the library that parses
  what the CDN sends, so that's where it matters most.
- **Never bundled:** glibc (a binary needs at least the build machine's),
  GPU drivers (Mesa or NVIDIA, libGL and EGL, VA-API drivers: they must
  match the kernel and GPU), and GTK where possible (themes, input
  methods for Arabic keyboards, Wayland). In the Flatpak, Flathub's
  runtime provides and patches these.
- **Licences:** mpv and FFmpeg are GPL or LGPL, and the app is MIT, which
  is compatible. Each package includes their licence texts and links to
  the exact sources we built.

### Format: Flatpak only (decision 2026-11-24)

One Linux package (owner's decision): one thing to keep working.

**Flatpak, for every Linux user.** It brings its own runtime (glibc, GTK,
FFmpeg) and our libmpv, so one build runs the same on every distro, with
nothing to install first. It's sandboxed, updates through GNOME Software
and KDE Discover, and Flathub is where Linux users look first.

*Built and checked on Linux 2026-11-24* (`tool/build_flatpak.sh`, 36 MB
bundle): it starts in the sandbox, loads Home over the network, keeps its
files in `~/.var/app/<id>/` (library, posters, log) with downloads in the
host's Videos folder, reaches NetworkManager, names the host system in
the log header and bug reports ("EndeavourOS (Flatpak)"), and a second
launch hands over to the open window. libmpv inside it plays H.264 and
AAC to the end through the runtime's FFmpeg. Left: the release workflow's
Linux job has never run (the AppArmor workaround in particular), and
playback of a real stream through the UI.

- **Manifest** `linux/flatpak/io.github.sharon_xa.cinemakom.yml`:
  - Runtime: the GNOME Platform 51 (GTK 3, FFmpeg).
  - Modules: libass 0.17.5, libplacebo 7.387.0 (OpenGL, no Vulkan) and
    libmpv from mpv 0.42.0 (OpenGL, Wayland, VA-API with Wayland and
    dmabuf interop, PulseAudio, PipeWire), pinned by checksum.
  - The app: the Flutter release bundle, built first on the host (CI:
    Ubuntu 24.04). Everything it links is in the runtime but libmpv.
  - mpv has no X11 support here (the SDK lacks some X11 libraries): on an
    X11-only desktop playback works, but hardware decoding may fall back
    to software. Wayland desktops are fine.
- **Permissions:**
  - `--share=network`, `--share=ipc`
  - `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`
  - `--socket=pulseaudio`
  - `--filesystem=xdg-videos`, for downloads
  - `--system-talk-name=org.freedesktop.NetworkManager`: connectivity_plus
    asks it whether the device is online.
  - Other folders, and Save a copy of the log, go through the file
    chooser portal.
  - Keeping the screen on already uses the Inhibit portal
    (wakelock_plus), so it needs no permission.
- **AppStream metainfo** `linux/packaging/io.github.sharon_xa.cinemakom.metainfo.xml`:
  English and Arabic, two screenshots (`docs/screenshots/desktop-*.png`),
  releases, and the required OARS content declaration (empty). That
  declaration describes the app for the store; it isn't a ratings
  feature. `appstreamcli validate` passes. Before Flathub: the
  screenshots show real film posters and a film frame, which reviewers
  may question.
- **Releases:** the release workflow builds the `.flatpak` (Linux job, on
  `ubuntu-24.04`) and attaches it. **Then** submit to Flathub (P3).
  Flathub reviews apps and prefers source builds: check its current rules
  for Flutter apps when submitting (building Flutter inside the SDK,
  offline). The app ID already matches the `io.github.<user>` form
  Flathub verifies through GitHub.

**The tarball is gone** (2026-11-24): the release workflow builds the
Flatpak instead, and the README's Linux section is one `flatpak install`.

**Not offered:** AppImage, AUR, `.deb`, `.rpm`, Snap. Flatpak covers all
of those users with one package that updates itself, and runs on Arch
too.

### Desktop integration (what makes it feel native)
- Done: desktop file with an Arabic name, `StartupWMClass` matching the app
  ID, icons at every size plus SVG.
- Done in P0: one instance (a second launch brings the open window to the
  front instead of running a second download engine on the same library).
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
| **P0** | Folders (§2), migration, one instance on both OSs | ✅ Linux 2026-11-24. Windows: the §2.1 steps |
| **P1** | Windows: runtime DLLs, a current libmpv, first real-machine run, Inno installer in CI | In Windows Sandbox: installs, starts, updates over itself and uninstalls cleanly. On the owner's machine: plays up to 4K and downloads |
| **P2** | Linux: metainfo, Flatpak bundle in CI, the tarball dropped, README points to the Flatpak | Built and checked on Arch (§3). Left: the first CI run, a real stream played through the UI, and a try on Fedora or Ubuntu in GNOME and KDE |
| **P3** | Flathub and winget | Listed, and updates arrive by themselves |
| **P4** | Signing (SignPath), MPRIS, update notice (§6) | As decided |

## 6. Decisions for the owner

1. **Publishing on Flathub and winget:** both are public listings with a
   review. OK to submit once P2 and P1 are done?
2. **"Update available" for the zip and the installer:** these don't
   update themselves. A check against GitHub Releases would be a
   third-party call, and AGENTS.md allows only the status page. Allow this
   one exception, or rely on Flathub and winget for updates?
3. **Settings in `~/.config`:** strict XDG, but it needs our own settings
   file instead of shared_preferences on Linux. Recommendation: not worth
   it now. Every other file moves in P0.
4. **Code signing:** apply to SignPath Foundation? It needs the project's
   public repository and a short application.
5. **Windows installer:** per user (recommended: no admin, installs over
   itself quietly) or for all users?

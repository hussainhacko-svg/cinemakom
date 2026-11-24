# Cinemakom on Apple TV (tvOS)

Apple TV support runs Cinemakom's remote-driven TV UI ([`lib/tv/`](../lib/tv/)) on **tvOS** via the isolated [`flutter-tvos`](https://github.com/fluttertv/flutter-tvos) toolchain, **without affecting Android, iOS, macOS, Linux, or Windows builds**.

---

## Architecture & Isolation

- **Dedicated entrypoint:** [`lib/main_tvos.dart`](../lib/main_tvos.dart) — leaves [`lib/main.dart`](../lib/main.dart) untouched for every other platform.
- **Dedicated Xcode runner:** [`tvos/`](../tvos/) (`Runner.xcodeproj`, `Runner.xcworkspace`, `Podfile`, `AppDelegate.swift`, `Info.plist`, `Assets.xcassets`) — completely independent of [`ios/`](../ios/).
- **Platform capabilities:** [`lib/core/platform/platform_info.dart`](../lib/core/platform/platform_info.dart) exposes `isAppleTv` and `supportsDownloads` (`!isAppleTv`). On all other targets `isAppleTv` is `false` and `supportsDownloads` is `true`.
- **Player engine (HDR):** [`lib/core/player/av_player_engine.dart`](../lib/core/player/av_player_engine.dart) drives Cinemakom's native tvOS HDR player host in [`tvos/Runner/AppleTvHdrPlayer.swift`](../tvos/Runner/AppleTvHdrPlayer.swift), embedding a direct `AVPlayerLayer` via `UiKitView` with **no** 8-bit `AVPlayerItemVideoOutput` attached and syncing `UIWindow.avDisplayManager.preferredDisplayCriteria` from the playing `AVAsset`. This enables hardware 4K **HDR10, HLG, and Dolby Vision** output plus Apple TV's **Match Dynamic Range** and **Match Frame Rate** (resetting cleanly to SDR when leaving the player), while Flutter composites `SubtitleLayer` (Dart SRT/VTT Arabic/English subtitles) and player controls above the video. `media_kit` is never initialized or linked on tvOS.
- **Storage & Downloads:** Because tvOS does not guarantee permanent bulk local storage (and purges `Library/Caches` under disk pressure), offline downloads are disabled on Apple TV (`supportsDownloads == false`: the Downloads tab and download buttons are hidden, and `background_downloader` is never started). The Drift SQLite database (watch history and favorites) is stored under `Library/Caches/db/cinemakom.sqlite`.
- **Canvas & 4K Artwork:** `_AppleTvViewport` in [`lib/tv/tv_app.dart`](../lib/tv/tv_app.dart) maps Apple TV's native `1920 × 1080 pt` display to Cinemakom's `960 × 540 dp` TV layout while scaling `devicePixelRatio` by `2×` (`4×` on Apple TV 4K, automatically enabling crisp 4K poster decoding and the 250 MB image cache).
- **Menu/Back button:** Pressing Menu/Back on the Home tab bar yields back to tvOS (`didPopRoute()` returns `false`) instead of calling `SystemNavigator.pop()`.
- **Wakelock:** [`tvos/Runner/AppDelegate.swift`](../tvos/Runner/AppDelegate.swift) handles `setWakelock` on the `io.github.sharon_xa.cinemakom/platform` channel via `UIApplication.shared.isIdleTimerDisabled`. A local pod shim at `tvos/LocalPods/wakelock_plus/` keeps `wakelock_plus` 1.8.2 compiling cleanly on tvOS without touching `.pub-cache` or iOS builds.

---

## Setup (macOS + Xcode)

```bash
# 1. Install flutter-tvos pinned to Cinemakom's Flutter version (.fvmrc = 3.47.9)
git clone https://github.com/fluttertv/flutter-tvos.git ~/flutter-tvos
git -C ~/flutter-tvos checkout --detach v3.47.9-tvos.1.11.5
~/flutter-tvos/bin/flutter-tvos precache
~/flutter-tvos/bin/flutter-tvos doctor
```

---

## Build & Run Commands

Use [`tool/build_tvos.sh`](../tool/build_tvos.sh) (uses `~/flutter-tvos/bin/flutter-tvos` by default, override via `FLUTTER_TVOS=...`):

```bash
# Build debug app for Apple TV Simulator
tool/build_tvos.sh simulator

# Run on a booted Apple TV Simulator or paired Apple TV device
tool/build_tvos.sh run <device-id>

# Build signed release for personal Apple TV / TestFlight
# (configure your Apple Development Team in tvos/Runner.xcodeproj first)
tool/build_tvos.sh release

# Unsigned release build (CI / compile check)
tool/build_tvos.sh release --no-codesign
```

### Sideloading / TestFlight on Personal Apple TV
1. Open `tvos/Runner.xcworkspace` in Xcode.
2. Select the `Runner` target → **Signing & Capabilities** → choose your **Team** and set a unique **Bundle Identifier** if needed.
3. Pair your Apple TV in Xcode (**Window → Devices and Simulators**).
4. Run `tool/build_tvos.sh run <apple-tv-device-id> --release` (or archive from Xcode for TestFlight).

---

## Verification

```bash
# Unit & Apple TV focus-trap tests (no simulator required)
~/flutter-tvos/bin/flutter-tvos test test/tv/boundaries_test.dart test/tv/apple_tv_test.dart

# Verify zero changes to other platforms
git diff ios/ android/ macos/ linux/ windows/ .github/workflows/release.yml
```

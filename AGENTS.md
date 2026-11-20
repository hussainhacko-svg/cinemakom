# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, etc.) working in this repository.

## What this is
**Cinemakom** is a cross-platform streaming frontend written in **Flutter** for **Android, iOS, Linux and Windows**. It is a client for the Cinemana API (`https://cinemana.shabakaty.com/api/android/`). We build **only the frontend**. There is no backend in this repo.

The original Kotlin/Jetpack Compose Android app is at `../cinematy`. It is low-quality AI-generated code: use it only for hints about which endpoints exist, and verify every behavior against the live API (see "Reference app" below).

## Read first
- `docs/API.md`: every endpoint, the required headers, parameters and JSON quirks. **This is the source of truth for the API.**
- `docs/DESIGN.md`: the "Marquee" design system (colours, type, spacing, components, performance rules). **Follow it for every screen.**
- `docs/PLAYER.md`: the detailed player plan (Phase 4): targets, architecture, features and milestones. **Read it before touching `lib/features/player` or `lib/core/player`.**
- `docs/TV.md`: the Android TV plan: a separate remote-driven UI in `lib/tv` and its focus rules. **Read it before any TV work.**
- `docs/PLAN.md`: architecture, tech stack, feature list and build phases. Check which phase we're in before starting work, and tick items off in §4 as they're finished.

## Commands
**Always use `fvm flutter` / `fvm dart` in this project.** It is pinned to **Flutter 3.47.9** (Dart 3.13) in `.fvmrc`, while the global `flutter` on PATH is 3.50.0.
```bash
fvm flutter pub get
fvm flutter analyze                      # must be clean before you finish
fvm flutter test                         # unit + widget tests
fvm dart run build_runner build -d       # only if freezed/drift codegen is in use
fvm flutter run -d linux                 # quickest way to check UI on this machine
fvm flutter run -d linux --dart-define=CINEMAKOM_TV=true  # the TV UI (lib/tv) in a 960×540 window: arrows, Enter = OK, Esc = Back
fvm flutter run -d <android-device-id>   # `fvm flutter devices` to list
fvm dart run tool/api_contract_check.dart  # live API contract check
fvm flutter test integration_test/screenshots_test.dart -d linux  # PNGs of the main screens in build/screenshots, for design review
fvm flutter test integration_test/tv_screenshots_test.dart -d linux  # the TV UI at 960×540, driven by remote keys (live API, real stream), PNGs tv-* in build/screenshots
fvm flutter test integration_test/player_engine_test.dart -d linux  # live player check (real media_kit)
fvm flutter test integration_test/player_test.dart -d linux  # the player end to end (live API, real engine)
fvm flutter test integration_test/downloads_test.dart -d linux  # downloads end to end (live CDN, ~50 MB): pause, resume, offline play
fvm flutter drive --profile --no-dds -d <android-device-id> --driver=test_driver/perf_driver.dart --target=integration_test/player_perf_test.dart  # 4K player frame times and memory on the phone. Also wipes the app's data
fvm flutter drive --profile --no-dds -d <android-device-id> --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart  # frame times on the phone at 120 Hz. Uninstalls the app first, wiping its data
fvm flutter drive --profile --no-dds -d <tv-ip>:5555 --driver=test_driver/perf_driver.dart --target=integration_test/tv_perf_test.dart --dart-define=PERF_HZ=60  # the TV UI's frame times (Home rows held, the 4K player) and memory on the TV. Wipes the app's data
fvm flutter build apk --release --split-per-abi  # APKs in build/app/outputs/flutter-apk/ (phones: app-arm64-v8a-release.apk)
tool/build_all.sh                        # every release this machine can build (Android APKs, Linux tarball) into dist/<git describe>/
```
**Why 3.47.9:** Flutter 3.50.0 has a Linux bug on NVIDIA's proprietary driver: the frame is drawn shifted by half the window, so you only see a quarter of the UI ([flutter#195885](https://github.com/flutter/flutter/issues/195885), [#196695](https://github.com/flutter/flutter/issues/196695)). The development machine has an NVIDIA GPU. Move back up (`fvm use <version>`, then restore `window_manager: ^0.7.0` and `sdk: ^3.14.0` in pubspec) only once a 3.50.x release fixes it, and check `fvm flutter run -d linux` renders the whole window. If a command fails because the SDK is missing, report it instead of installing toolchains yourself.

## Architecture rules
- Folders are organized by feature: `lib/core` (network, storage, platform), `lib/data` (models, parsers, repositories), `lib/features/<feature>` (screen, widgets, providers). See PLAN.md §3.
- **State and DI:** Riverpod. **Routing:** go_router. **HTTP:** dio. **DB:** drift. **Player:** media_kit (desktop, iOS) and video_player/ExoPlayer (Android). **Downloads:** background_downloader, behind `Downloader` (`lib/core/downloads`; `background_file_downloader.dart` is the only file that imports it). `DownloadsRepository` owns the queue, events and offline lookups; the player plays a finished download from disk by itself.
- **Only `lib/core/network` builds URLs or sets headers.** Screens and widgets never call Dio directly. They go through repositories.
- **One shared header map** (`User-Agent`, `Referer`, `Origin`, see API.md) is used for API calls, images, video streams and downloads. Never copy it somewhere else.
- **The JSON is inconsistent.** IDs and titles come under several different key names. Parse with the tolerant helpers in `lib/data/parsers`, not generated `fromJson`. Parsers must skip bad items and never throw.
- Keep new endpoints in `api_endpoints.dart` and document them in `docs/API.md` in the same change.
- **Long lists** (anything paged) are a `MediaSource` in `lib/data/paging/media_sources.dart`, shown through `pagedMediaProvider` with `PagedGridSlivers` (grid) or `SourceRow` (a row). Don't write paging logic in screens. Lists scroll infinitely (decision 2026-11-19).
- **Opening pages:** use `openTitle` / `openGenre` / `openList` (`lib/app/navigation.dart`). They push inside the current tab, so the nav bar stays and back works. New page types get a route in `_browse` in `router.dart`. The player is the exception: `openPlayer` pushes the full-screen `/watch/:id` route above the tabs.
- **Images** go through `MediaImage` (shared headers, decoded at display size, no fade). **Errors** go through `ErrorView` / `errorMessage` (it asks the status page once). **Loading** is `BulbLoader`, never a spinner or shimmer.
- **Player:** two engines behind `PlayerEngine`: **ExoPlayer on Android** (`exo_player_engine.dart`, the only file that imports video_player; mpv stuttered on 4K there) and **media_kit (mpv) everywhere else** (`media_kit_engine.dart`, the only file that imports media_kit). Everything else uses `PlayerEngine`. Android has no styled (ASS) subtitles (`supportsStyledSubtitles`). `PlayerController` (`lib/features/player`) owns playback and recovery. Follow `docs/PLAYER.md` (and its §6 and §13 findings: never parse mpv error text, an early "completed" is a failure, a failed open stays "buffering", ExoPlayer stops on every error and resets its position: `errorsStopPlayback`).
- **TV:** the TV UI is separate, in `lib/tv` (docs/TV.md). Never add `isTv` branches to phone or desktop widgets, and never let `lib/features` or `lib/app` import `lib/tv`. `isTouchMobile` is only for platform behaviour (orientation, notification permission).
- **No automatic provider retries:** every `ProviderScope` / `ProviderContainer` uses `retry: noRetry` (from `main.dart`). `ApiClient` already retries a failed GET once; screens show errors with "Try again".

## Conventions
- Dart style: `flutter_lints` / analysis_options. Prefer `final`, `const` constructors, and small widgets. Run `dart format` only on the files you changed: formatting a whole folder rewrites other people's files and generated ones (`*.g.dart`).
- **Design:** there is **one theme** (Marquee). No light/dark modes and no theme setting. Use `MarqueeColors`, `MarqueeText`, `MarqueeSpace` and `MarqueeRadius` from `lib/app/theme/`, or `Theme.of(context)`. Never hardcode colours, fonts or sizes in widgets. No shadows, blur or gradients (performance and style, see DESIGN.md §6).
- **Logo and app icons** are generated by `tool/brand/generate.py` (DESIGN.md §7). Never edit the generated icons, splash files or `brand_paths.g.dart` by hand. Change the generator and re-run it.
- **Localization:** every user-facing string goes in the ARB files (`app_ar.arb`, `app_en.arb`). The app supports **English (default) and Arabic**. On first launch it asks the user which language to use. Arabic switches the layout to RTL, so every screen must work in both directions. Use directional APIs (`EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end`), never hardcoded left or right. Captions that mix Latin and Arabic parts ("720p · 270 م.ب") use `context.joinMeta` / `context.isolate` (`lib/app/widgets/media_text.dart`), or the parts swap places in RTL.
- **Orientation (mobile):** only through `setBrowseOrientation` / `setPlayerOrientation` (`lib/core/platform/orientation.dart`). Browsing screens are portrait unless Settings allows rotation. The player is landscape and restores the setting on exit. The Android manifest declares `MainActivity` portrait so the app never starts sideways; TVs launch `TvActivity` (the same activity, declared landscape, `LEANBACK_LAUNCHER` only). Never force a sensor orientation that ignores the system auto-rotate lock.
- **Refresh rate (Android):** `MainActivity` asks for the fastest display mode, so the frame budget is 8.3 ms (DESIGN.md §6). Not on TVs, where a display mode is an HDMI output mode: their budget is 16.7 ms (docs/TV.md §9).
- **Platforms:** check `isDesktop` / `isMobile` through `lib/core/platform`. Touch gestures (brightness and volume swipes, double-tap) are mobile only. Desktop needs keyboard shortcuts and mouse hover.
- **Responsive layout:** below 600 dp width use a bottom `NavigationBar`, at 600 dp and up use a `NavigationRail`, and from 1200 dp an extended rail. The tabs are Home, Search, Library, Downloads and Settings. Each screen's layout is in DESIGN.md §8.
- **Tests:** when you add or change a parser, add or update a fixture in `test/fixtures/` and a test in `test/parsers/`. Fixtures are real API responses captured by `tool/capture_fixtures.dart`. Widget tests of screens use `pumpApp()` and `fixtureApi()` from `test/helpers/app_harness.dart` (no network, no images). `pumpAndSettle` never returns while a `BulbLoader` is on screen (it animates), so make sure loads finish. `pumpApp()` swaps media_kit for a `FakeEngine` (`test/features/player/fake_engine.dart`); player logic is tested with it under `fake_async`. To *see* a change, run `integration_test/screenshots_test.dart` on Linux and look at the PNGs. **TV screens:** `pumpApp(tester, tv: true)` (960 × 540 dp at 2×; `freeSpace:` sets the TV's free storage), `TvDriver` for remote keys (`test/tv/tv_driver.dart`; Esc stands in for Back, `tester.binding.handlePopRoute()` for Android's system Back), and `expectNoTraps` (`test/tv/reachability.dart`) for every new TV screen. Pump `SizedBox()` before `pumpApp` again, or the app keeps its state. Downloads write real files: let them finish with `runAsync` (the `_io` helper in the download tests). A platform channel nobody mocks never answers in a test, so wrap native calls in an overridable provider.
- **Android video:** the emulator renders no video at all (PLAYER.md §13), so don't test playback on it. The owner tests on a real phone with a release APK (see Commands).

## Reference app (`../cinematy`): keep token use low
- Useful files: `app/src/main/java/com/example/cinematy/network/ApiService.kt` and `models/MediaModels.kt` (the parsers to port).
- `MainActivity.kt` (2.7k lines), `ui/HomeScreen.kt` and `ui/VideoPlayerScreen.kt` (~1.8k lines each) are large. **Grep them for what you need. Don't read them in full.**
- Never modify the reference app.

## Don'ts
- **Zero censorship.** Never filter, hide, blur or skip content. Always send parental `level=0` (the unrestricted level). Don't build parental controls, kids modes, "family friendly" filters or scene skipping, and don't use `skippingDurations` / `checkVideoParentalLevel` / `parent_skipping`.
- **No ratings of any kind.** Don't show, store, sort by or filter by ratings: no star or IMDb scores (`stars`, `rate`), no age or parental ratings (`filmRating`, `seriesRating`), no likes or dislikes, no "Top rated" rows and no minimum-rating filters. Don't parse these fields into models.
- Don't add features that need a Shabakaty login (server-side history, likes, comments, subscriptions). They're out of scope for v1.
- Don't hardcode the current year (e.g. in AdvancedSearch `year=1900,<year>`). Compute it.
- Don't commit secrets, tokens or client IDs taken from the web frontend bundle.
- Don't publish, push or release builds unless asked.
- **Git:** commit directly on `main`. Don't create branches unless the owner asks for one.
- Never call Shabakaty's telemetry, IP-check or ad hosts (`api/info/*`, `whatismyip`, `shabakaty.com/clip/`, Sentry, `aj2376.online`; full list in `docs/API.md` §1). The only third-party call allowed is the public status page, and only after API calls fail.

# Cinemakom Android TV: Build Plan

**Goal:** make the existing Android APK work natively on **Android TV / Google TV** (e.g. TCL Google TV) with a standard TV remote (D-pad, OK/Select, Back, Media keys), while keeping phone and tablet behavior unchanged.

No separate TV build or CI job is needed — one Android APK supports phones, tablets, and Android TV simultaneously. Read this alongside [`DESIGN.md`](DESIGN.md) and [`PLAYER.md`](PLAYER.md).

---

## 1. Status Overview

| Milestone | Scope | Done when | Status |
|---|---|---|---|
| **TV-1** | Manifest, TV banner, runtime detection, orientation & TV platform flags | Installs on Android TV with home-screen banner, starts in landscape, hides phone-only settings, phone behavior unchanged | [x] |
| **TV-2** | TV-remote player controls, focusable accelerated `SeekBar`, menu autofocus | Full playback, seeking, Skip Intro, Up Next, Quality/Subtitles/Speed/Episodes menus work with remote only | [x] |
| **TV-3** | D-pad browsing polish across all screens (focus rings, `HomeHero`, `Search`, `MediaRow`, `AppShell`, RTL) | Every screen is navigable from launch to playback using only D-pad + Select + Back in EN and AR | [x] |
| **TV-4** | Automated tests, emulator pass, real TCL TV pass, docs update | `flutter analyze` & `flutter test` green, verified on TCL TV via release APK, docs updated | [ ] *(tests & docs done; TCL TV check pending)* |

---

## 2. Decisions *(2026-11-20)*

1. **Downloads on TV:** keep the Downloads tab and download buttons visible on Android TV.
2. **OK/Select while video plays (controls hidden):** toggle Play/Pause immediately and briefly show controls (YouTube TV / Netflix style); if **Skip intro** or **Up next** is showing, activate it directly.
3. **Focus styling:** keep the exact Marquee layout with 2 px `bulb` focus rings (`DESIGN.md` §5) and TV safe padding — no card-scaling animations.
4. **Rollout:** implement all milestones in one pass (manifest + detection, TV remote player controls, and full D-pad browsing polish).

---

## 3. Current Gaps Audited in the Codebase

| Area | Current behavior | Impact on Android TV |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | No `LEANBACK_LAUNCHER`, no `touchscreen required="false"`, no `android:banner`, hardcoded `screenOrientation="portrait"` | App doesn't appear on the TV home screen and launches forced into portrait |
| `lib/core/platform/orientation.dart` | `setBrowseOrientation` locks Android to `portraitUp` by default | Browsing screens stay squashed/rotated on TV until entering the player |
| `lib/core/platform/platform_info.dart` | Only exposes `isDesktop`, `isMobile`, `isAndroid` (no `isTv`) | TV gets phone touch gestures, screen-lock button, and Settings → Screen rotation |
| `lib/features/player/player_screen.dart` | `CallbackShortcuts` binds `arrowLeft`/`Right`/`Up`/`Down` globally; `ControlsOverlay` is not wrapped in `ExcludeFocus` when hidden | D-pad arrows are stolen for seek/volume instead of navigating Subtitles/Quality/Episodes/Skip Intro; hidden buttons can catch focus |
| `lib/features/player/widgets/seek_bar.dart` | Raw `GestureDetector` with no `Focus` node | Unreachable by D-pad; no accelerated remote scrubbing |
| `lib/features/home/widgets/home_hero.dart` | All 10 banners sit in a `Stack` with `IgnorePointer` + `AnimatedOpacity` (no `ExcludeFocus`), and `_sideBySide = 900.0` | D-pad cycles through 9 invisible Play/Favorite buttons; on a `960×540 dp` Android TV viewport (~816 dp content width), the hero stacks vertically and fills almost the entire screen |
| `lib/features/search/search_screen.dart` | Bare `TextField` directly in the focus tree | Landing D-pad focus on Search immediately pops the TV keyboard and traps arrow keys in the text cursor |
| `lib/app/widgets/controls.dart`, `choice_picker.dart`, `settings_screen.dart`, `app_shell.dart` | Rely on Material's faint default `focusColor` instead of a `bulb` focus ring | Focused chips, tabs, rows, and dialog options are nearly invisible from 10 feet on dark `#15100C`/`#221A14` surfaces |
| `lib/app/widgets/media_row.dart` | "See all" sits above the horizontal `ListView` with default focus traversal and edge-hugging scroll | Pressing Down near the right edge snags on "See all" instead of moving cleanly between poster rows |

**What already works well for TV:**
- **ExoPlayer (`ExoPlayerEngine`):** hardware 4K H.264 decoding via `video_player` texture view.
- **Wide layout:** Android TV renders UI at `1920×1080 @ 2.0× = 960×540 dp` (even on 4K TVs). `AppShell` already uses the compact `NavigationRail` at `600–1199 dp`, Details uses two columns, and pickers/menus open as dialogs/popovers.
- **Focus rings (partial):** `PosterCard` already draws a 2 px `bulb` border on focus, and `ControlsOverlay` uses `withFocusRing` on player buttons.

---

## 4. Implementation Checklist

### Milestone TV-1: Manifest, TV Banner & Runtime Detection

- [x] **TV banner generator (`tool/brand/generate.py`):**
  - [x] Add `android_tv` banner generation (`640×360` px at `xhdpi`, `320×180` dp) on Night `#15100C` with the Cinemakom ticket mark (`DESIGN.md` §7).
  - [x] Generate `android/app/src/main/res/drawable-xhdpi/tv_banner.png` (never hand-edit generated brand files).
- [x] **Android manifest (`android/app/src/main/AndroidManifest.xml`):**
  - [x] Add `<uses-feature android:name="android.hardware.touchscreen" android:required="false" />`.
  - [x] Add `<uses-feature android:name="android.software.leanback" android:required="false" />`.
  - [x] Set `android:banner="@drawable/tv_banner"` on `<application>`.
  - [x] Add `<category android:name="android.intent.category.LEANBACK_LAUNCHER" />` to `MainActivity`'s intent filter.
  - [x] Change `android:screenOrientation="portrait"` to `unspecified` so TVs are not forced into portrait before `onCreate`.
- [x] **Native TV detection & phone startup orientation (`MainActivity.kt`):**
  - [x] Detect TV via `UiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION || packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)`.
  - [x] Set `requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT` in `onCreate` when **not** on TV (preserving phone upright startup from frame 0).
  - [x] Expose `MethodChannel("io.github.sharon_xa.cinemakom/platform")` method `isTv`.
- [x] **Dart platform flags (`lib/core/platform/` & callers):**
  - [x] Query `isTv` once at startup in `lib/main.dart` before `runApp`.
  - [x] Add `isTv`, `isTouchMobile` (`isMobile && !isTv`), and `@visibleForTesting bool? debugIsTvOverride` in `lib/core/platform/platform_info.dart`.
  - [x] Make `setBrowseOrientation` and `setPlayerOrientation` no-ops when `isTv` (`lib/core/platform/orientation.dart`).
  - [x] Hide Settings → Screen rotation when `isTv` (`lib/features/settings/settings_screen.dart`).
  - [x] Skip `askToNotify()` when `isTv` (`lib/core/downloads/background_file_downloader.dart`).
- [x] **Done when:** Android APK declares Leanback support + banner, starts in landscape on TV, keeps portrait on phones, and exposes `isTv` cleanly to Flutter & tests.

---

### Milestone TV-2: TV-Remote Player Controls (`lib/features/player/`)

- [x] **Separate TV input from phone touch gestures (`player_screen.dart`):**
  - [x] Wrap player body in `GestureLayer` only when `isTouchMobile` (no brightness/volume swipes or pinch on TV).
  - [x] Hide the top-bar screen-lock button when `isTv` (`if (isTouchMobile)`).
  - [x] Keep `AudioFocus`, `WakelockPlus`, and `ExoPlayerEngine` active on TV.
  - [x] Wrap `ControlsOverlay` in `ExcludeFocus(excluding: !_visible || _locked)` so hidden controls never steal D-pad focus.
  - [x] Use a 5 s controls auto-hide timeout on TV (vs 3 s on mobile/desktop) and reset it on every D-pad key event.
- [x] **Always-active TV media keys (`player_screen.dart`):**
  - [x] `mediaPlayPause` → toggle play/pause.
  - [x] `mediaPlay` → play; `mediaPause` → pause.
  - [x] `mediaRewind` / `mediaFastForward` → seek −10 s / +10 s.
  - [x] `mediaTrackNext` → next episode.
  - [x] Do **not** intercept hardware Volume Up/Down on TV (leave to Android TV system volume).
- [x] **State-aware D-pad handling on TV (`player_screen.dart`):**
  - [x] **Controls hidden (`!_visible`):**
    - [x] `arrowLeft` / `arrowRight` → quick-seek −10 s / +10 s (with hold/tap acceleration) and show brief seek-bar / time feedback without trapping focus.
    - [x] `arrowUp` / `arrowDown` → reveal controls and focus the centre **Play/Pause** button.
    - [x] `select` / `enter` → activate **Skip intro** or **Up next** if showing; otherwise toggle play/pause immediately and briefly show controls.
    - [x] `goBack` / `escape` → save progress and exit the player.
  - [x] **Controls visible (`_visible`):**
    - [x] Release `arrowUp` / `arrowDown` / `arrowLeft` / `arrowRight` to Flutter's directional focus traversal across top bar chips, centre playback buttons, `SeekBar`, Episodes, Next episode, Skip intro, and Up next.
    - [x] `goBack` / `escape` → hide controls first (second Back exits the player).
- [x] **Focusable `SeekBar` with accelerated scrubbing (`seek_bar.dart`):**
  - [x] Add a `Focus` node and visible `bulb` focus ring around the track/thumb.
  - [x] While focused, `arrowLeft` / `arrowRight` scrubs in place and displays the sprite preview bubble above the thumb.
  - [x] Accelerate scrub step while holding/tapping Left/Right (`10 s → 30 s → 60 s`) and commit seek on key release / Select (or short settle delay).
  - [x] `arrowUp` / `arrowDown` moves focus cleanly out of the seek bar to centre buttons or bottom actions.
- [x] **Player menus & Episodes panel (`chip_menus.dart`, `episodes_panel.dart`):**
  - [x] Autofocus the currently selected item (quality, subtitle, speed, fit, or current episode) when opened.
  - [x] Closing with Back restores focus to the chip/button that opened the menu.
- [x] **Done when:** A movie and a series episode can be played, paused, fast-scrubbed, switched in quality/subtitles/speed/episodes, skipped past intro, and exited using only a TV remote.

---

### Milestone TV-3: D-Pad Browsing Polish Across All Screens

- [x] **Shared 2 px `bulb` focus styling (`lib/app/theme/marquee_theme.dart` & widgets):**
  - [x] Add 2 px focus rings across theme buttons (`FilledButton`, `OutlinedButton`, `TextButton`, `IconButton`) and custom interactive widgets matching `DESIGN.md` §5 (no card scaling).
  - [x] Apply clear `bulb` focus indicators to:
    - [x] `AppShell` `NavigationRail` destinations (`lib/app/shell/app_shell.dart`)
    - [x] `FilterPill` and `Segmented` (`lib/app/widgets/controls.dart`)
    - [x] `_ChoiceRow` (`lib/app/widgets/choice_picker.dart`, plus autofocus on the currently selected choice)
    - [x] `SettingsRow` (`lib/features/settings/`)
    - [x] First-launch language picker option cards & Continue button (`lib/features/onboarding/`)
    - [x] Search genre tiles & recent-search rows (`lib/features/search/search_screen.dart`)
    - [x] Continue watching cards, plus a focusable "Remove" action on TV instead of relying on long-press (`lib/features/library/`, `lib/features/home/widgets/continue_row.dart`)
    - [x] Details actions (Play/Resume, Favorite, Download, Trailer), genre chips, season chips, episode range chips, episode rows, and Cast & crew cards (`lib/features/details/`)
    - [x] Library & Downloads rows (focusable pause/resume/cancel/delete actions)
- [x] **Home hero (`lib/features/home/widgets/home_hero.dart`):**
  - [x] Wrap inactive `_HeroInfo` children in `ExcludeFocus(excluding: i != index)` so D-pad never steps through 9 hidden Play/Favorite buttons.
  - [x] Enable side-by-side hero layout on TV (`isTv || width >= _sideBySide`) so on `960×540 dp` TVs the hero fits above the fold with the first poster row visible below.
  - [x] Add D-pad-accessible previous/next banner switching (since TV users cannot swipe `PageView`) and pause auto-advance while the hero has focus.
- [x] **Row-to-row D-pad flow & scroll comfort (`lib/app/widgets/media_row.dart`, `paged_grid.dart`):**
  - [x] Prevent D-pad Down from poster rows snagging unexpectedly on the next row's "See all" button (move focusable "See all" card to the end of each horizontal row on TV).
  - [x] Ensure focused cards scroll comfortably into view (`Scrollable.ensureVisible` on TV) and trigger infinite-scroll pagination reliably under D-pad movement.
- [x] **Search TV focus wrapper (`lib/features/search/search_screen.dart`):**
  - [x] Prevent D-pad landing on the search box from immediately popping the full-screen TV keyboard or trapping arrow keys in the cursor.
  - [x] Enter text input mode on OK/Select; exit cleanly back to D-pad navigation on Back/Done.
  - [x] Ensure D-pad Down moves smoothly from the search box to kind chips, recent searches, and genre tiles.
- [x] **NavigationRail ↔ content & Back behavior (`lib/app/shell/app_shell.dart`):**
  - [x] Moving toward content from the rail enters the active tab cleanly; moving from the start edge of content enters the rail.
  - [x] Pressing Back from a root tab moves focus to the `NavigationRail` (or returns to Home) before exiting the app.
- [x] **Overscan safety & Arabic RTL:**
  - [x] Apply TV safe-area padding (`16 dp` outer padding around `AppShell` in addition to responsive gutters) so nothing clips on TVs with overscan.
  - [x] Verify D-pad `arrowLeft` / `arrowRight` follows visual direction in Arabic RTL (rail on right edge; player seek bar remains physical LTR per `PLAYER.md` §2).
- [x] **Done when:** Every screen in both English and Arabic can be browsed end-to-end with only D-pad + Select + Back, with clear `bulb` focus visibility at `960×540 dp` and zero focus traps.

---

### Milestone TV-4: Verification & Documentation

- [x] **Automated tests (`flutter analyze` + `flutter test`):**
  - [x] Unit tests for `platform_info` (`isTv` / `isTouchMobile` / `debugIsTvOverride`) and `orientation` no-op on TV.
  - [x] Widget test: Settings hides Screen rotation on TV, keeps Downloads visible.
  - [x] Widget test: First-launch language picker → Home reachable via D-pad + Select.
  - [x] Widget test: `HomeHero` has no focusable ghost buttons on inactive banners and uses side-by-side layout at `960×540` when `isTv == true`.
  - [x] Widget test: Search box focuses without trapping arrows and activates typing on Select.
  - [x] Widget test: Player hidden-controls quick-seek, media keys, Play/Pause on Select, Up reveal.
  - [x] Widget test: Player visible-controls D-pad navigation, focusable `SeekBar` accelerated scrubbing, Back hides controls first, menus autofocus active choice.
  - [x] Widget test: Arabic RTL D-pad navigation in browsing and player.
- [ ] **Android TV emulator check:**
  - [ ] Verify Leanback home-screen banner, landscape startup, `960×540` layout density, and D-pad focus on every tab.
- [ ] **Real TCL TV check (release APK):**
  - [ ] Sideload release APK (`armeabi-v7a` or `arm64-v8a`) via ADB or GitHub Release.
  - [ ] Verify home-screen banner and launch straight into landscape.
  - [ ] Verify 1080p and 4K ExoPlayer playback, Arabic & English subtitle legibility at 10-foot distance.
  - [ ] Verify remote Play/Pause, hold-to-scrub seeking with preview frames, Quality/Subtitles/Episodes menus, Skip Intro, Up Next, and Back behavior.
  - [ ] Verify Search with the TV on-screen keyboard and Downloads flow.
- [x] **Docs update:**
  - [x] Link and record Android TV support in [`PLAN.md`](PLAN.md), [`DESIGN.md`](DESIGN.md), and [`PLAYER.md`](PLAYER.md).
  - [x] Verify `flutter analyze` and `flutter test` pass with zero warnings.

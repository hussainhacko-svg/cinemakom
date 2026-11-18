# Cinemakom (Flutter): Build Plan

**Goal:** rebuild the Cinematy Android app (Kotlin/Jetpack Compose, `../cinematy`) as one Flutter codebase for **Android, iOS, Linux and Windows**. The app is a frontend for the Cinemana API (see [`API.md`](API.md)). There is no backend work.

**Scope**
- Match every feature of the Kotlin app.
- Add the features that the newly found endpoints make possible.
- Leave out anything that needs a Shabakaty account (server-side history, likes, comments, subscriptions). It stays out of scope unless we decide to add sign-in later.

---

## 1. Prerequisites

| Item | Notes |
|---|---|
| Flutter SDK | ✅ The project is pinned to **Flutter 3.47.9** (Dart 3.13) in `.fvmrc`, so use `fvm flutter …`. The global `stable` (3.50.0) has an NVIDIA Linux rendering bug (see AGENTS.md → Commands) |
| Java | ✅ OpenJDK 17 at `/usr/bin/java` (needed by the Android Gradle build) |
| Android | ✅ SDK at `~/Android/Sdk` (with cmdline-tools), emulator `Medium_Phone_API_37.0`. `flutter doctor` is green. The new Android CLI no longer needs a license step |
| Linux | ✅ `clang cmake ninja-build pkg-config gtk3` and **`mpv`/libmpv** (needed by media_kit). On Arch: `sudo pacman -S mpv` |
| Windows | Visual Studio 2022 with the "Desktop development with C++" workload. media_kit ships its own libmpv |
| iOS | Requires a Mac with Xcode. Builds can't happen on this machine, so plan on CI (e.g. Codemagic or GitHub Actions macOS runners) or a Mac |

Create the project:
```bash
cd ~/Projects/flutter/cinemakom
flutter create --project-name cinemakom --org io.github.sharon_xa --platforms android,ios,linux,windows .
```
> ✅ Application ID: **`io.github.sharon_xa.cinemakom`**, based on the GitHub account `sharon-xa`. Hyphens aren't allowed in IDs, so `-` becomes `_`. **Never change it after the first store release.**

---

## 2. Tech stack

| Concern | Kotlin app | Flutter choice | Why |
|---|---|---|---|
| State management and DI | Compose state / ViewModels | **flutter_riverpod** | Testable and handles async state well. No codegen needed to start |
| Navigation | Manual state in MainActivity | **go_router** (with `StatefulShellRoute` for tabs) | Deep links, back-stack per tab, and desktop back handling |
| HTTP | Retrofit + OkHttp + Gson | **dio** | One interceptor adds the required headers. Also gives timeouts, cancellation and retry |
| JSON | Gson with lenient fallbacks | **Hand-written tolerant parsers** (`dart:convert`) | The API changes key names across endpoints, so generated `fromJson` breaks. Port `parseMediaItems`, `parseCategories`, `parseSeriesEpisodes` and `parseSubtitles` |
| Immutable models | Kotlin data classes | **freezed** (optional) or plain `final` classes | |
| Images | Coil | **cached_network_image** | Accepts `httpHeaders`. Its cache uses sqflite, so **desktop needs `sqflite_common_ffi`** (see §6) |
| Video player | Media3 ExoPlayer | **media_kit** + media_kit_video | The only mature player that covers all four platforms. Supports per-media HTTP headers, external subtitles and quality switching |
| Local database | Room v4 (downloads, history, favorites) | **drift** (sqlite3 3.x) | Typed SQL, reactive streams, and it works on desktop. sqlite3 3.x bundles SQLite through build hooks. **Don't add `sqlite3_flutter_libs`**: it is end-of-life |
| Key-value settings | SharedPreferences | **shared_preferences** | |
| Downloads | Android DownloadManager | **background_downloader** | Android, iOS, Windows, Linux. Custom headers, pause/resume, progress and notifications |
| Localization | Inline ar/en strings | **flutter_localizations + intl (ARB files)** | English is the default. Arabic is fully supported, and the layout must work in RTL |
| Paths | Android external storage | **path_provider** | |
| Player extras | Android APIs | `screen_brightness`, `volume_controller` (mobile), `wakelock_plus`, `window_manager` (desktop fullscreen) | |
| Material / Cupertino | `package:flutter/material.dart` | **material_ui**, **cupertino_ui** | Flutter 3.47+ moved Material and Cupertino out of the SDK. Import `package:material_ui/material_ui.dart`. `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations` now come from these packages, not `flutter_localizations` |
| Lints and tests | — | `flutter_lints` (or `very_good_analysis`), `flutter_test`, `mocktail`, `integration_test` | |

---

## 3. Architecture

Organized by feature, in layers: **data → domain → presentation**, with Riverpod providers connecting them.

```
lib/
  main.dart                     # bootstrap: MediaKit.ensureInitialized, sqflite ffi on desktop, ProviderScope
  app/
    app.dart                    # MaterialApp.router, theme, locale, RTL
    router.dart                 # go_router + tab shell
    theme/                      # the one Marquee theme: colour tokens, type scale, ThemeData
    l10n/                       # app_ar.arb, app_en.arb
  core/
    network/
      api_client.dart           # Dio instance, base URL, header interceptor, logging
      api_endpoints.dart        # every path from API.md as builder functions
      api_exception.dart
    json/
      json_utils.dart           # firstNonBlank(), parseIntLoose(), unescapeUrl()
    storage/
      database.dart             # drift DB: downloads, watch_history, favorites
      preferences.dart          # language, default resolution, default subtitle
    platform/
      platform_info.dart        # isDesktop / isMobile helpers
  data/
    models/                     # MediaItem, MediaDetails, Episode, VideoSource, SubtitleTrack,
                                # Category, Language, StaffMember, StaffPage, VideoGroup, SkipRange
    parsers/                    # tolerant parsers ported from MediaModels.kt
    repositories/
      catalog_repository.dart   # home rows, groups, featured, latest, genres, by-category(+language), FAQ
      search_repository.dart    # base64 title search + AdvancedSearch, merged, de-duplicated and ranked
      media_repository.dart     # details, episodes, seasons, streams, subtitles, related, skip ranges, getVideosByIds, staff pages
      library_repository.dart   # favorites + continue watching (drift)
      downloads_repository.dart # background_downloader + drift
  features/
    home/  search/  genre/  details/  player/  continue_watching/
    favorites/  downloads/  settings/  staff/  faq/
      # each: <feature>_screen.dart, widgets/, <feature>_providers.dart
test/
  fixtures/                     # captured real JSON responses, one per endpoint
  parsers/                      # parser unit tests run against fixtures
  repositories/                 # tests against a mocked Dio
```

Key rules:
- Only `core/network` knows URLs and headers. Screens never call Dio directly.
- All JSON handling goes through `data/parsers`. Repositories return clean domain models, and parsers never throw on bad input. They skip it.
- **Image, video and download requests reuse the same header map** (`ApiClient.defaultHeaders`). Keeping it in one place stops the four call sites drifting apart, which was the problem in the Kotlin app.

---

## 4. Features

Product rules (AGENTS.md): **zero censorship** (always the unrestricted level, no parental features) and **no ratings of any kind** (no scores, no likes, no "Top rated", no rating filters). Every feature below is backed by an endpoint verified in `docs/API.md`.

### 4.1 Core
- [ ] **App shell:** five tabs (Home, Continue, Favorites, Downloads, Settings). Bottom `NavigationBar` below 600 dp width, `NavigationRail` at 600 dp and up.
- [ ] **Home:** hero carousel from `banner` (wide covers), curated video groups, Featured, Latest movies, Latest series, Most watched (`views_desc`), New releases by year (`r_desc`), Recently added (`desc`), and genre rows. Load the above-the-fold sections first and the rest after.
- [ ] **Genre detail:** paged grid (30 per page, offset paging that stops on a short page) with sort (recently added, newest release, most watched) and kind (movies or series). Use `fallbackGenres` when the genre lists fail to load.
- [ ] **Search:** 400 ms debounce, three requests in parallel (title search, AdvancedSearch movies, AdvancedSearch series), merged, de-duplicated and ranked. Never send an empty query. The year range is computed.
- [ ] **Details** (bottom sheet on mobile, page or side panel on desktop): poster, synopsis, year, duration, genres, audio languages, trailer, IMDb link, season and episode picker. Episodes show as "Episode N" (the API has no episode titles) with the season image. Add to favorites, download.
- [ ] **Player:**
  - quality selection (default from settings, closest match, 2160p when listed)
  - subtitles (Arabic, English or off, default from settings; one track per language, SRT preferred)
  - playback speed
  - aspect/fit modes
  - double-tap seek (mobile)
  - next episode
  - resume from saved position
  - brightness and volume swipe gestures (mobile only)
  - always refetch stream URLs before playing (signed URLs expire after ~5 days)
- [ ] **Continue watching:** progress saved to drift on pause, exit and every N seconds. Resume episodes using the series, season and episode fields.
- [ ] **Favorites:** add, remove and list.
- [ ] **Downloads:** video plus subtitle, live progress and speed, files grouped by series, delete, offline playback with the local subtitle file.
- [ ] **Settings:**
  - language (English or Arabic, default English. Arabic flips the layout to RTL)
  - default resolution (2160p/1080p/720p/480p/360p, default 1080p)
  - default subtitle (Arabic, English or Off, default Arabic)
- [ ] **First-launch language picker:** the first time the app opens, ask the user to pick English or Arabic before showing Home. Save the choice. It can be changed later in Settings.
- [x] **Branding:** the Marquee logo (ticket stub carrying ك, `docs/DESIGN.md` §7), app icons for all four platforms, and the native splash screens, all generated by `tool/brand/generate.py`. *Still to do: the in-app splash with the bulb loader (Phase 2), and installing the Linux .desktop file and icons (Phase 8 packaging).*

### 4.2 Extras the API supports
- [ ] **More like this** on details, from the recommendation service (`recommend.shabakaty.com`: same franchise, then shared cast), falling back to `relatedVideos`.
- [ ] **Cast and crew** row on details (`actorsInfo`, `directorsInfo`, `writersInfo`). Tapping a person opens an **actor/director page** (`staff/actorID/...`).
- [ ] **Skip intro** button in the player, from `introSkipping` (`MediaDetails.introRanges`), which can hold two ranges.
- [ ] **Seek-bar previews** from `video_thumbnails` sprite sheets (`SeekPreview.frameAt`). Popular titles have them; hide the preview when a title has none.
- [ ] **Season picker** that loads first (`videoSeasonNumber`), with episodes loaded per season.
- [ ] **"See all"** page for each video group (`videoListPagination`).
- [ ] **Genre × language filter** (`categoryLangFreqVideo` + `videosByCategoryAndLanguage`), e.g. Anime = Animation (57) × Japanese.
- [ ] **Advanced search filters:** kind, genre (`category_id`), year range, actor or director name (`staffTitle`). No rating filter, no sort (the server ignores it).
- [ ] **Library refresh:** update favorites and history metadata with `POST getVideosByIds` (40 numeric IDs per request).
- [ ] **FAQ / help** screen in Settings (`faqQuestion`).

### 4.3 Not possible or excluded
- **Comments:** switched off server-wide (`showComments: false` everywhere).
- **Collections, "Popular" (`popularFilms`), season posters:** the endpoints return nothing or fail with 500.
- **View counts:** `videoViewsNumber` is always 0.
- **Ratings, likes, age ratings:** excluded by the no-ratings rule.
- **Parental filtering, scene skipping, kids mode:** excluded by the zero-censorship rule.
- **Anything that needs a Shabakaty login.**

---

## 5. Phases

> **Status (2026-11-19):** Phases 0 and 1 are done, and so is the design system with the logo and app icons (`docs/DESIGN.md`). **Next: Phase 2 (app shell).** The project runs on Flutter 3.47.9 through fvm (see AGENTS.md → Commands).

Each phase ends with something that runs. **Every phase is tested on Android and Linux.** Windows is tested from Phase 4 on, iOS from Phase 6 on.

### Phase 0: Setup ✅ *(done 2026-11-19)*
- [x] Fix the Flutter install, run `flutter doctor`, then `flutter create` (§1).
- [x] Add dependencies, lints and the folder layout from §3. `git init`. Write a `CLAUDE.md` or README that points to `docs/`.
- ~~Optional: CI~~ Skipped by decision. Run `fvm flutter analyze` and `fvm flutter test` locally.
- [x] **Done when:** an empty app runs on Android and Linux. Checked on the `Medium_Phone_API_37.0` emulator and the Linux desktop.

### Phase 1: Data layer *(most important)* ✅ *(done 2026-11-19)*
- [x] `ApiClient` with the headers, a 30 s timeout and a debug logger. Large responses are decoded on a background isolate.
- [x] Write `api_endpoints.dart` covering every public endpoint in `API.md`.
- [x] Port the tolerant parsers, and add the new models (staff, intro ranges, languages, FAQ, seek previews). Comments are switched off server-wide, so they aren't modeled.
- [x] Write `tool/capture_fixtures.dart`, a script that calls each endpoint once and saves the JSON to `test/fixtures/` (signed-URL credentials redacted).
- [x] Unit-test every parser against the fixtures, including edge cases (string vs number IDs, `\/` URLs, the `episodeNummer` spelling, object vs array roots).
- [x] Repositories (catalog, search, media) with fake-client tests. Staff pages live in `MediaRepository`.
- [x] **Done when:** `fvm flutter test` is green and a debug screen lists real data from every endpoint. Run the live checks with `fvm dart run tool/api_contract_check.dart` and `fvm flutter test integration_test/api_debug_test.dart -d linux`.
- [x] **API deep dive (2026-11-19):** reverse-engineered from the website bundle, its network traffic, a field survey and edge probes. This corrected the sort codes, the search encoding, the batch limit, banner images, paging end and episode titles. See `docs/API.md`.
- [x] **Second API deep dive (2026-11-19):**
  - **Sources:** every guest page of the website, the full bundle, the Android app 5.3.3 (read-only) and a 2,000-request field survey.
  - **New behaviour in the code:** `episode_flag` labels (finales, double episodes); styled ASS subtitles; stale stream URLs refetched past the API cache; sprite sheets with real row counts; placeholder images rejected; banner episode links; seasons fallback.
  - **Search and sorting:** `AdvancedSearch` needs `type` and ORs title and staff; title and release-date sorts.
  - See `docs/API.md` §8 for the product decisions this raised.

### Phase 2: App shell
- go_router with the tab shell and per-tab back stacks.
- The single Marquee theme (`lib/app/theme/`, done), bundled fonts, ARB localization in en and ar, RTL switching.
- First-launch language picker (English or Arabic), shown once before Home and saved to preferences.
- Preferences provider and the Settings screen.
- Responsive navigation (bar or rail).
- **Done when:** a fresh install asks for the language, you can switch tabs, change the language live, and settings survive a restart.

### Phase 3: Browsing
- Home (all rows, carousel, shimmer placeholders, pull-to-refresh), genre detail with infinite scroll, search, and details with episodes.
- Image loading with the headers. Pick card, HD and backdrop sizes the same way the Kotlin `posterUrl` / `hdPosterUrl` / `backdropUrl` do.
- **Done when:** you can browse, search and open details for movies and series on Android and Linux.

### Phase 4: Player
- media_kit with headers, a quality menu, external subtitles (srt/vtt) with Arabic font rendering, speed, fit modes, next episode, saving position and resuming.
- **Mobile:** gestures, forced landscape, wakelock.
- **Desktop:** keyboard shortcuts (space, ←/→ seek, ↑/↓ volume, F fullscreen, Esc), mouse-hover controls, fullscreen through `window_manager`.
- Skip intro.
- **Done when:** a movie and a full series play smoothly on Android, Linux and Windows.

### Phase 5: Library
- drift tables (`watch_history`, `favorites`), the Continue and Favorites screens, and a background metadata refresh with `getVideosByIds`.
- **Done when:** history and favorites survive a restart and resume works.

### Phase 6: Downloads
- background_downloader for video plus subtitle, with the headers.
- Progress, speed, pause/resume/cancel, notifications on mobile.
- Storage location per platform:
  - Android: app-specific external directory
  - iOS: Application Support
  - desktop: a folder the user picks, defaulting to `~/Videos/Cinemakom`
- Offline playback, delete, and grouping by series.
- iOS background download limits (URLSession) need testing on a real device.
- **Done when:** a download finishes, plays offline with subtitles, and survives an app restart in the middle.

### Phase 7: New features
- Everything in §4.2: cast and crew, actor pages, related titles, extra home rows, group "see all", genre × language filter, advanced filters, comments, FAQ.

### Phase 8: Polish and release
- App icons and splash screen on all platforms, empty, error and offline states, accessibility (semantics, text scaling), and performance (image cache size, list `cacheExtent`).
- Packaging:
  - Android: APK/AAB
  - Windows: MSIX or an installer (Inno Setup)
  - Linux: AppImage or Flatpak
  - iOS: IPA through TestFlight

---

## 6. Platform notes and risks

| Risk | Mitigation |
|---|---|
| `cached_network_image` → sqflite crashes on Linux and Windows | In `main.dart` on desktop: `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`. Or use a cache manager backed by drift or files |
| libmpv is missing on a user's Linux install | List it as a dependency in the Flatpak or AppImage. Show a clear error if the player fails to start |
| The API checks headers (Referer, Origin, User-Agent) | All requests go through the shared header map. If streams break on one platform, compare against the Kotlin app first |
| The API is undocumented and can change without warning | Parsers stay tolerant. Fixture tests catch changes. Re-run the capture script to compare |
| Unknown stream formats (mp4 vs HLS) | Check `container` in the `transcoddedFiles` fixtures. media_kit plays both |
| `popularFilms`, `latestVideosItems`, `collectionVideos` return nothing | Leave them out of the UI until they return data |
| Arabic text and RTL in subtitles and mixed-language titles | Bundle an Arabic font (e.g. Noto Kufi Arabic or Cairo). Use `Directionality` per text when a title mixes scripts |
| iOS can't be built on this Linux machine | Use a CI macOS runner or a Mac. Keep iOS-specific code small |
| Desktop input (no touch) | Controls must work with keyboard and mouse. Gestures are mobile only. Show hover states and scrollbars on desktop |
| Data from the old Android app (Room) | **Not migrated.** This is a new app with a new database. Document it for existing users |

---

## 7. Testing

- **Unit:** every parser against real fixtures, plus repositories with a mocked Dio. This matters most, because the JSON is where things break.
- **Widget:** the cards, the home rows (loading, error and data states), the settings toggles, RTL layout.
- **Integration:** use `integration_test` to run launch → search → open details → play for 5 seconds. Run it on an Android emulator and a Linux desktop.
- **Manual check before each release:** go through every §4 checkbox on Android, Linux and Windows, and iOS when available.

---

## 8. Open decisions
1. ~~Application ID and org~~ ✅ `io.github.sharon_xa.cinemakom`.
2. Riverpod with or without codegen (`riverpod_generator`). The proposal is to start without it.
3. Details as a bottom sheet everywhere, or a full page on desktop. The proposal is a sheet on mobile and a page with a two-column layout on desktop.
4. Download folder on desktop: fixed, or chosen by the user. The proposal is a default folder the user can change in Settings.
5. Add Shabakaty sign-in later (unlocks server-side history, likes, comments)? Out of scope for v1.

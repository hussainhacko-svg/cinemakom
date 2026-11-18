# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, etc.) working in this repository.

## What this is
**Cinemakom** is a cross-platform streaming frontend written in **Flutter** for **Android, iOS, Linux and Windows**. It is a client for the Cinemana API (`https://cinemana.shabakaty.com/api/android/`). We build **only the frontend**. There is no backend in this repo.

The original Kotlin/Jetpack Compose Android app is at `../cinematy`. Use it only as a behavior reference (see "Reference app" below).

## Read first
- `docs/API.md`: every endpoint, the required headers, parameters and JSON quirks. **This is the source of truth for the API.**
- `docs/PLAN.md`: architecture, tech stack, feature list and build phases. Check which phase we're in before starting work, and tick items off in §4 as they're finished.

## Commands
```bash
flutter pub get
flutter analyze                      # must be clean before you finish
flutter test                         # unit + widget tests
dart run build_runner build -d       # only if freezed/drift codegen is in use
flutter run -d linux                 # quickest way to check UI on this machine
flutter run -d <android-device-id>   # `flutter devices` to list
```
Flutter is managed with **fvm**. The global SDK is at `~/fvm/default/bin`, which is on PATH. If a command fails because the SDK is missing, report it instead of trying to install toolchains yourself.

## Architecture rules
- Folders are organized by feature: `lib/core` (network, storage, platform), `lib/data` (models, parsers, repositories), `lib/features/<feature>` (screen, widgets, providers). See PLAN.md §3.
- **State and DI:** Riverpod. **Routing:** go_router. **HTTP:** dio. **DB:** drift. **Player:** media_kit. **Downloads:** background_downloader.
- **Only `lib/core/network` builds URLs or sets headers.** Screens and widgets never call Dio directly. They go through repositories.
- **One shared header map** (`User-Agent`, `Referer`, `Origin`, see API.md) is used for API calls, images, video streams and downloads. Never copy it somewhere else.
- **The JSON is inconsistent.** IDs and titles come under several different key names. Parse with the tolerant helpers in `lib/data/parsers`, not generated `fromJson`. Parsers must skip bad items and never throw.
- Keep new endpoints in `api_endpoints.dart` and document them in `docs/API.md` in the same change.

## Conventions
- Dart style: `flutter_lints` / analysis_options. Prefer `final`, `const` constructors, and small widgets.
- **Localization:** every user-facing string goes in the ARB files (`app_ar.arb`, `app_en.arb`). The app supports **English (default) and Arabic**. On first launch it asks the user which language to use. Arabic switches the layout to RTL, so every screen must work in both directions. Use directional APIs (`EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end`), never hardcoded left or right.
- **Platforms:** check `isDesktop` / `isMobile` through `lib/core/platform`. Touch gestures (brightness and volume swipes, double-tap) are mobile only. Desktop needs keyboard shortcuts and mouse hover.
- **Responsive layout:** below 600 dp width use a bottom `NavigationBar`, at 600 dp and up use a `NavigationRail`.
- **Tests:** when you add or change a parser, add or update a fixture in `test/fixtures/` and a test in `test/parsers/`. Fixtures are real API responses captured by `tool/capture_fixtures.dart`.

## Reference app (`../cinematy`): keep token use low
- Useful files: `app/src/main/java/com/example/cinematy/network/ApiService.kt` and `models/MediaModels.kt` (the parsers to port).
- `MainActivity.kt` (2.7k lines), `ui/HomeScreen.kt` and `ui/VideoPlayerScreen.kt` (~1.8k lines each) are large. **Grep them for what you need. Don't read them in full.**
- Never modify the reference app.

## Don'ts
- Don't add features that need a Shabakaty login (server-side history, likes, comments, subscriptions). They're out of scope for v1.
- Don't hardcode the current year (e.g. in AdvancedSearch `year=1900,<year>`). Compute it.
- Don't commit secrets, tokens or client IDs taken from the web frontend bundle.
- Don't publish, push or release builds unless asked.

# Cinemakom Player: Build Plan (Phase 4)

**The player is the most important part of the app.** This file is the detailed plan for PLAN.md Phase 4, and it replaces that phase's short list. Read it with `docs/API.md` §3 (streams, subtitles, intro ranges, seek previews) and `docs/DESIGN.md` §8 (the player screen).

---

## 1. What "the best player" means here

These are the targets. Every milestone below is checked against them.

| Area | Target |
|---|---|
| **Start** | The first frame appears within 3 s of tapping Play on 1080p over a normal connection, even though 1080p files aren't fast-start (API.md §3). A `BulbLoader` shows while it loads, never a spinner or a black screen |
| **Seeking** | A seek inside the buffer is instant. A seek outside it shows the loader and plays within 2 s |
| **Never stuck** | Every failure ends in a clear message with **Try again**. An infinite loader is a bug. Expired URLs (403) and dropped connections recover by themselves at the same position |
| **Never lose progress** | At most 10 s of progress is lost, whatever happens: app killed, crash, unplugged laptop |
| **Smooth controls** | The controls run at 60 fps on a mid-range Android phone while 1080p plays. Position updates repaint only the seek bar and the clock |
| **Switching keeps your place** | Changing quality, subtitles or episode keeps the position (quality), the subtitle and speed choices (episode), and the play/pause state |
| **Works everywhere** | Touch on Android and iOS, keyboard and mouse on Linux and Windows, in English (LTR) and Arabic (RTL) |

## 2. Decisions

*Made 2026-11-19.*
1. **Resume is stored in drift from Phase 4.** The `watch_history` table and its repository are built now (save and read). Phase 5 only adds the Library UI and the metadata refresh.
2. **The seek bar always runs left → right**, in Arabic too. The ±10 s buttons, double-tap zones and swipe-to-seek follow the same physical direction. Only the top bar's text and chips follow RTL.
3. **Next episode autoplays with a countdown.** An "Up next" card appears near the end, and a 10 s countdown starts the next episode. **Next episode** is always available.
4. **Extras in Phase 4:** subtitle size and delay, seek-bar previews (moved up from Phase 7), and a controls lock on mobile.
5. **Not in Phase 4:** picture-in-picture, casting, background audio, lock-screen media controls (§12).
6. Already decided (PLAN.md §4.1): 2160p is a normal quality, with an always-visible quality chip. "Arabic (styled)" is an extra subtitle choice for ASS tracks. Stream URLs are fetched right before playing and again on a 403. When the API fails, ask the status page once.

## 3. What already exists

| Piece | Where | Notes |
|---|---|---|
| Streams, highest first, refetched past the API cache when stale | `MediaRepository.streams` | Add `streams(id, fresh: true)` to always bypass the cache after a 403 (a URL can claim days of validity and still fail) |
| Subtitles, one plain track per language, plus styled ASS | `MediaRepository.subtitles`, `oneTrackPerLanguage` | `MediaDetails.subtitles` also carries them |
| Intro ranges | `MediaDetails.introRanges` (`SkipRange.contains`) | 1–3 ranges |
| Seek previews | `MediaRepository.seekPreview`, `SeekPreview.frameAt` | `null` for 49% of titles |
| Episodes, sorted, with labels | `MediaRepository.episodes`, `Episode.numbering` | Never episode titles |
| Default quality and subtitles | `settingsProvider` (`PreferredQuality.height` = `VideoSource.height`) | |
| Shared headers | `ApiClient.defaultHeaders` | Passed to `Media(httpHeaders:)`. Never copied |
| Status page | `StatusRepository.cinemanaHealth()`, `ErrorView` / `errorMessage` | |
| Packages | media_kit 1.2.6, media_kit_video 2.0.1, media_kit_libs_video, wakelock_plus, screen_brightness, volume_controller, window_manager 0.6.0 | `MediaKit.ensureInitialized()` already runs in `main.dart` |
| Where Play plugs in | `details_screen.dart` (`onPressed: null`), `home_hero.dart` (opens details for now), `episode_list.dart` (rows not tappable) | |

**media_kit facts this plan relies on** (read from the package source):
- `Media(uri, httpHeaders:, start:)`: per-media headers and a start position.
- `SubtitleTrack.uri(url, title:, language:)` loads an external subtitle file.
- `PlayerConfiguration`: `bufferSize` (default 32 MB, which is only about 12 s of 4K), `libass`, `libassAndroidFont` / `libassAndroidFontName` (Android only, set before mpv starts), `title`.
- Its mpv defaults: `cache=yes`, `cache-on-disk=yes`, `hr-seek=yes`, **`network-timeout=5`** (too short for multi-GB files on a slow node), `keep-open=yes`.
- `NativePlayer.setProperty(name, value)` sets any mpv property at runtime.
- The `Video` widget hides its own subtitle text when `libass` is on, but `SubtitleView` is exported, so we can place our own.
- Hardware decoding is on by default (`hwdec: auto`).

## 4. Architecture

```
lib/
  core/
    player/
      player_engine.dart        # PlayerEngine interface: open, play/pause, seek, rate, volume, subtitle, streams of state
      media_kit_engine.dart     # the only file that imports media_kit (mpv options, headers, error mapping)
      subtitle_fonts.dart       # copies the bundled Arabic font to disk for libass (desktop and iOS)
    storage/
      database.dart             # drift DB (watch_history now; favorites and downloads later)
  data/
    models/
      playback_request.dart     # what to play: a title, an optional episode, an optional start
      watch_progress.dart       # one row of watch_history, plus isFinished / resumeAt rules
    repositories/
      library_repository.dart   # watch_history: save, read, latest per series (favorites in Phase 5)
  features/player/
    player_screen.dart          # route page: Video + overlay layers, lifecycle (orientation, wakelock, fullscreen)
    player_controller.dart      # PlayerController (Riverpod Notifier): the playback session
    player_state.dart           # immutable PlayerState (source, quality, subtitle, speed, fit, status, error…)
    quality.dart                # pickQuality(): closest to the preference
    up_next.dart                # next-episode rules and the countdown
    widgets/
      controls_overlay.dart     # scrim, top bar, centre buttons, bottom bar, auto-hide
      seek_bar.dart             # played / buffered / thumb, LTR, scrub with preview
      seek_preview_frame.dart   # one sprite cell, drawn with drawImageRect
      chip_menus.dart           # subtitles, quality, speed, fit: sheet below 600 dp, popover from 600 dp
      subtitle_layer.dart       # Flutter-drawn plain subtitles (size setting, lifts above the controls)
      skip_intro_button.dart
      up_next_card.dart
      episodes_panel.dart       # series: pick another episode without leaving the player
      gesture_layer.dart        # mobile: taps, double-tap seek, swipes, pinch, lock
      shortcuts.dart            # desktop: Shortcuts/Actions and mouse handling
```

**Rules**
- **Only `media_kit_engine.dart` imports media_kit.** Everything else talks to `PlayerEngine`, so the controller is unit-tested with a `FakeEngine` and the screens are widget-tested without native code.
- **`PlayerController` owns the session.** Screens call intents like `togglePlay()`, `seekBy()`, `selectQuality()`, `selectSubtitle()`, `nextEpisode()`. The controller also owns recovery and saving progress.
- **Headers:** the engine receives `ApiClient.defaultHeaders` and passes it to `Media(httpHeaders:)`. Subtitle URLs and sprite sheets get the same headers (sprites through `MediaImage` or the shared header map).
- **Sources are a sealed type:** `RemoteSource(videoId)` now, `LocalSource(filePath, subtitlePath)` in Phase 6, so offline playback reuses the same player.
- **Route:** `/watch/:id` is a **top-level route on the root navigator**, outside the tab shell, so the nav bar is hidden. `openPlayer(context, request)` goes in `navigation.dart`. The `PlaybackRequest` travels as `extra`. A bare `/watch/:id` (deep link, hot restart) rebuilds it from the ID.
- **Performance:** the `Video` texture is never inside an `Opacity`, `ClipRRect` or `saveLayer`. Controls fade with one `FadeTransition` on the overlay only. Position text updates at most 4× a second, and the seek bar is a `RepaintBoundary` driven by a `ValueListenable`. `PlayerState` excludes the position, so menus and chips don't rebuild every tick.

## 5. Engine setup (mpv)

Set in `media_kit_engine.dart`, once per player.

| Option | Value | Why |
|---|---|---|
| `bufferSize` | 64 MB mobile, 192 MB desktop | 32 MB holds about 12 s of 4K (22 Mbit/s). Read-ahead must cover several seconds of 4K |
| `network-timeout` | `20` | The default 5 s drops slow CDN nodes on the tail read that non-fast-start files need |
| `stream-lavf-o` | `reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=5` | Reconnects at the HTTP layer before we see an error |
| `demuxer-readahead-secs` / `cache-secs` | 20 / 60 (desktop), 20 / 30 (mobile) | Fast seeks near the playhead without filling a phone's disk |
| `cache-on-disk` | `yes` desktop, `no` mobile (memory cache only) | Keeps phone storage free. Revisit after the spike |
| `hwdec` | `auto` (default) | 4K H.264 needs hardware decoding on phones. Fall back to `no` once on decoder errors |
| `libass` | `true` | Needed for the styled ASS track, and on Android it's the only way to give libass a font (§7.2) |
| `sub-visibility` | toggled per track at runtime | Plain tracks are drawn by Flutter, styled tracks by libass (§7.2) |
| `title` | the media title | Window and task-switcher title on desktop |

`network-timeout`, the reconnect options and the cache sizes are starting values. The spike (§10, M0) confirms them on Android and Linux.

## 6. Playback flow

**Opening a title** (`PlayerController.open(request)`):
1. **In parallel:** `details` (if not passed in), `streams`, `subtitles`, `seekPreview`, the saved progress, and for a series the episode list.
2. **Pick the quality** (§7.1) and the subtitle (§7.2).
3. **Pick the start:** the request's `start`, or the saved position if resume applies (§7.6), or 0.
4. **Open** `Media(url, httpHeaders: defaultHeaders, start:)`, add the subtitle track, set the speed, then play.
5. **While playing:** save progress (§7.6), watch for intro ranges (§7.5) and the end of the episode (§7.7).

**Failure and recovery** (inside the controller):

| What happens | What the player does |
|---|---|
| The stream answers 403, or mpv can't open it | Remember the position, call `streams(id, fresh: true)`, reopen the same quality at that position. Once per minute at most; after that, show the error |
| The network drops mid-play | mpv reconnects first. If playback stays stalled for 15 s, reopen at the last position with backoff (2, 5, 10 s). Show "Reconnecting…" over the loader |
| The streams or details request fails | `ErrorView` (it asks the status page once, so "Cinemana is having problems" when it's down) with **Try again** |
| No streams at all | "This title isn't available right now", with Back |
| Decoder error | Retry once with `hwdec=no`. If 4K still fails, offer the next lower quality |
| A subtitle fails to load | Keep playing without it and show a short note: "Subtitles couldn't be loaded" |
| The status page is checked | Only after API calls fail, never for CDN errors |

Every error message goes in the ARB files.

## 7. Features

### 7.1 Quality
- **Default:** `pickQuality(sources, preferred)` takes the exact match, else the nearest **lower** quality, else the lowest one above it. 2160p counts like any other quality.
- **Chip:** always visible in the top bar: "1080p", or "4K" for 2160p (`bulb` badge style, DESIGN.md §5).
- **Menu:** every available quality, highest first, with the current one in `bulb` and a check. 2160p shows "4K · about 10 GB per hour" as its caption.
- **Switching:** reopen the new URL at the current position, keeping pause state, speed and the subtitle (external tracks are re-added after `loadfile`). The old frame stays on screen until the new one arrives.
- The pick in the menu applies to this session (and the next episodes), not to Settings.

### 7.2 Subtitles
- **Default from Settings:** Arabic, English or Off. If the language is missing, use Off and show nothing (no silent switch to the other language).
- **Choices:** Off, then one plain track per language (SRT preferred, `oneTrackPerLanguage`), then **"Arabic (styled)"** when an ASS track exists. Plain Arabic stays the default.
- **How they're drawn (hybrid):**
  - **Plain tracks:** mpv parses the file, `sub-visibility=no`, and `subtitle_layer.dart` draws the current text from the player's subtitle stream in Flutter. It uses IBM Plex Sans Arabic / IBM Plex Sans (cream text with a dark outline, no box). It lifts above the controls when they're shown, stays on screen in Fill mode, and follows the size setting. Each line gets its own `Directionality` from its script.
  - **Styled ASS track:** `sub-visibility=yes`, so libass renders it into the frame with its own styles. The Flutter layer hides.
  - **Font for libass:** the ASS files name fonts the device won't have ("Adobe Arabic"). Bundle **IBM Plex Sans Arabic Medium** as the fallback. On Android it's set through `libassAndroidFont` / `libassAndroidFontName`. On desktop and iOS, `subtitle_fonts.dart` copies it from the assets to the app support folder at startup and sets `sub-fonts-dir` / `sub-font`.
- **Size** (new setting, Settings → Playback): Small, Medium (default), Large. It applies to plain tracks, and to ASS through `sub-scale` (0.85 / 1 / 1.2).
- **Delay:** in the subtitle menu, "Sync" with −0.5 s / +0.5 s steps and a reset, shown as "+1.5 s". It's set with mpv `sub-delay`, works for both renderers, and is kept for the rest of the session (not saved).

### 7.3 Speed
0.5×, 0.75×, 1×, 1.25×, 1.5×, 1.75×, 2× with pitch correction (mpv's default). The chip shows "1×". It's kept for the session, across episodes.

### 7.4 Fit
**Fit** (whole frame, letterboxed; the default), **Fill** (crop to fill the screen), **Stretch**. The chip cycles through them (icon plus a short toast "Fill"). On mobile, pinch out = Fill and pinch in = Fit. Done with `Video(fit:)`. Plain subtitles stay on screen in Fill because Flutter draws them.

### 7.5 Skip intro
- While the playhead is inside an intro range (`SkipRange.contains`), show **Skip intro** (outlined pill, at the end side above the seek bar, as in the design). It jumps to the range's `end`.
- The button stays visible even when the controls are hidden, and for 8 s at most per range, then folds into the controls.
- Desktop: **S** skips. On a two-range title (cold open, then intro) each range gets its own button.

### 7.6 Resume and history (drift)
- **Table `watch_history`:**
  - `videoId` (primary key: the movie or episode ID)
  - `seriesId` (null for movies), `season`, `episode`
  - `positionMs`, `durationMs`, `finished`, `updatedAt`
  - display metadata: `titleEn`, `titleAr`, `posterUrl`, `kind`
  - Never stream URLs.
- **Saving:** every 10 s while playing, plus on pause, after a seek, on episode change, on leaving the player, and when the app goes to the background (`AppLifecycleListener`). Writes are cheap upserts.
- **Finished:** 95% watched, or less than 2 min left. A finished episode resumes the series at the next one.
- **Resume:** offered when ≥ 30 s were watched and the video isn't finished. The player starts there directly and shows "Resuming from 14:32 · Start over" for 5 s.
- **Details:** the primary button becomes "Resume · S2 E5 · 14 min left" (DESIGN.md §8), and episode rows show progress and watched numerals (DESIGN.md §5).
- **Home's Continue watching row** reads the same table. Phase 5 adds the Library tab on top.

### 7.7 Next episode and Up next
- **Next** = the next entry in the sorted episode list, across seasons. Double episodes are one entry. Nothing after the last episode.
- **Next episode** button at the end of the bottom bar (design). Desktop: **N**.
- **Up next card:** it appears at the "finished" point (less than 2 min left or 95%), in the bottom end corner. It shows the season image, "Up next · Season 2 · Episode 6", **Play now** and **Hide**. In the **last 10 s** a countdown ring fills, then the next episode starts. If the file ends sooner (a short credits roll), the countdown starts at the end.
- **Still watching?** After 3 automatic episodes in a row with no input, pause and ask "Still watching?" instead of continuing (saves data overnight, especially in 4K).
- **Episodes panel** (series only): an "Episodes" button next to Next episode opens a side panel (bottom sheet on phones) with the season chips and episode rows from Details. Picking one switches in place and keeps quality, subtitle choice and speed.

### 7.8 Seek-bar previews
- When dragging the thumb or hovering the bar (desktop), show the frame from `SeekPreview.frameAt` above the thumb (120×68, radius 6, with the time under it). No frame (title without sprites, broken sheet, past the last sheet) = the time alone.
- Sheets load through the shared headers and the image cache. Prefetch the sheet under the playhead and the next one when the player opens. The frame is drawn with `drawImageRect`, not by cropping a widget.

### 7.9 Buffering and loading
- Opening and seeking outside the buffer: `BulbLoader` in the centre, controls still usable.
- Buffering mid-play: the loader replaces the play/pause icon inside the `bulb` circle after 300 ms (no flicker on short stalls).
- The seek bar shows the buffered range in `velvetStrong` (design).

## 8. Controls (from the design mock)

**Layout** (landscape, controls over a 60% `night` scrim):
- **Top bar:**
  - Start side: back, then the title (`title` style) and "Season 2 · Episode 5" (`caption`, `dust`).
  - End side: outlined chips for **subtitles** ("Arabic"), **quality** ("1080p" / "4K"), **speed** ("1×"), and **fit**.
  - Desktop adds a **fullscreen** button. Mobile adds the **lock** button.
- **Centre:** back 10 s, the `bulb` play/pause circle, forward 10 s.
- **Bottom:**
  - Above the bar, at the end side: **Skip intro** or the Up next card.
  - Then elapsed time, the seek bar (`bulb` played, `velvetStrong` buffered, `velvet` track), and the remaining time ("−28:18").
  - Last: **Episodes** (series) and **Next episode**.
- **Portrait on phones:** the player forces landscape, so there's no portrait layout. Tablets and desktop windows use the same layout at any size. Below about 480 dp wide, the chips collapse into one "⋯" menu.

**Visibility:**
- Controls show on tap, mouse move or a key press, and hide after 3 s of no input while playing.
- They stay visible while paused, while a menu is open, while scrubbing and during errors.
- **Skip intro** and the Up next card stay visible when the controls hide.

**Menus:** each chip opens a bottom sheet below 600 dp and an anchored popover from 600 dp (like `showChoicePicker`). One row per choice, with the current one in `bulb` and a check. Playback continues while a menu is open.

**RTL:**
- The seek bar, the times on either side of it, the ±10 s buttons and the gesture zones keep their **physical** positions (decision 2).
- Times use Western digits (DESIGN.md §2).
- The top bar, the chip order, the menus, Skip intro, the Up next card and the Episodes panel follow `start`/`end`.

## 9. Platform specifics

### 9.1 Mobile (Android, iOS)
- **On enter:** landscape only, immersive mode (`SystemUiMode.immersiveSticky`), wakelock while playing. **On exit:** restore orientation, system UI, wakelock and brightness.
- **Gestures** (`gesture_layer.dart`, physical sides):

| Gesture | Action |
|---|---|
| Tap | Show or hide the controls |
| Double-tap left / right third | −10 s / +10 s. Repeated taps add up ("+30 s") with a ripple on that side |
| Horizontal drag | Seek, with the preview frame and the target time |
| Vertical drag, left half | Brightness (app-level, through `screen_brightness`, restored on exit) |
| Vertical drag, right half | Volume (system volume through `volume_controller`, without the system slider) |
| Pinch | Fill / Fit |

  - Drags start 24 dp from the screen edges, so the system back gesture and notification shade still work.
  - The brightness and volume levels show as a slim vertical bar (`bulb` on `velvet`) with an icon.
- **Controls lock:** a lock button in the top bar. While locked, touches are ignored except a small unlock button that appears on tap and hides after 3 s.
- **Audio interruptions:** pause on headphone unplug, incoming calls and other apps taking audio focus. iOS plays sound even with the silent switch on. This needs **`audio_session`** (new dependency): it is the standard package for this and doesn't add background playback.
- **Back:** the system back button or gesture leaves the player (saving progress), or unlocks first when locked, or closes an open menu first.

### 9.2 Desktop (Linux, Windows)
- **Mouse:**
  - Moving shows the controls. The cursor hides with them after 3 s.
  - Click on the video = play/pause. Double-click = fullscreen. Scroll wheel = volume.
  - Hover states on every control. Hovering the seek bar shows the preview and time.
- **Fullscreen** through `window_manager` (enter, exit, and restore the previous size).
- **Volume** is mpv's volume (0–100), saved in preferences.
- **Keyboard** (`Shortcuts`/`Actions`, the same keys in both languages):

| Key | Action |
|---|---|
| Space, K | Play / pause |
| ← / → | −10 s / +10 s |
| Shift + ← / → | −60 s / +60 s |
| ↑ / ↓ | Volume ±5 |
| M | Mute |
| F, double-click | Fullscreen |
| Esc | Leave fullscreen, else close a menu, else leave the player |
| S | Skip intro |
| N | Next episode |
| C | Next subtitle choice |
| [ / ] | Slower / faster |
| 0–9 | Jump to 0–90% |

- Every control is reachable with Tab and has a 2 px `bulb` focus ring (DESIGN.md §5).

## 10. Milestones

Each milestone ends with something that runs, and is checked on **Android and Linux**. Windows is checked from M8 on (needs a Windows machine or VM).

| # | Milestone | Done when |
|---|---|---|
| **M0** | **Spike** (throwaway code on the debug screen, `features/debug/`): play a 1080p non-fast-start movie, a 4K movie and an anime episode with headers; measure start time; hybrid subtitles (Flutter-drawn SRT plus libass ASS with the bundled font, on Android and Linux); `sub-fonts-dir` at runtime on desktop; how a 403 and a network drop look on the error/log streams; quality switch at a position; 4K on the emulator and on a real phone | The numbers and findings are written into §5 and §13 of this file, and any choice they overturn is changed here first |
| **M1** | `PlayerEngine`, `MediaKitEngine`, `PlayerController` and `PlayerState`, no UI. `pickQuality`, subtitle choice, recovery (403 → `streams(fresh: true)`), `streams(fresh:)` in `MediaRepository` | Unit tests with `FakeEngine` cover open, quality pick, subtitle pick, 403 recovery, network-drop recovery and errors |
| **M2** | `/watch/:id` route, `openPlayer`, the player screen with the basic controls (back, play/pause, ±10 s, seek bar, times, buffering loader, auto-hide). Play wired from Details, the hero and episode rows | A movie and an episode play from the app, on Android and Linux |
| **M3** | Chip menus: subtitles (with size and delay), quality, speed, fit. Settings → Subtitle size | Every switch keeps the position and the other choices |
| **M4** | drift `database.dart`, `watch_history`, `LibraryRepository`, saving and resume, Details' Resume button, episode progress in the rows, Home's Continue watching row | Force-stop mid-episode, relaunch, and resume within 10 s of where it stopped |
| **M5** | Series: Next episode, the Up next card and countdown, "Still watching?", the Episodes panel | A full season plays through by itself, and switching episodes keeps the choices |
| **M6** | Skip intro and seek-bar previews | Both work on a title that has them, and nothing shows on one that doesn't |
| **M7** | Mobile: orientation, immersive mode, wakelock, gestures, the lock, `audio_session` interruptions | Checked by hand on the emulator and a real Android phone |
| **M8** | Desktop: shortcuts, mouse, cursor hiding, fullscreen, saved volume. First Windows run | Every shortcut in §9.2 works on Linux and Windows |
| **M9** | Hardening: profile mode on a mid-range phone (60 fps controls, memory with 4K), Arabic/RTL pass, every error state, the integration test | Every target in §1 is met, and PLAN.md §4.1 Player is ticked |

## 11. Testing
- **Unit:**
  - `pickQuality` (exact, lower, higher, 4K, missing 1080p).
  - Subtitle choice (missing language, styled only).
  - `isFinished` / resume rules.
  - Next-episode order (gaps, double episodes, season boundaries).
  - The Up next countdown and "Still watching?" (with `fake_async`).
  - Recovery paths, with `FakeEngine`.
- **Repository:** `LibraryRepository` on an in-memory drift database. `streams(fresh: true)` on the fake API client.
- **Widget** (`pumpApp`, `fixtureApi`, `FakeEngine` instead of media_kit):
  - Controls show and hide.
  - Chips and menus.
  - Skip intro inside and outside a range.
  - The Up next card.
  - The seek bar staying LTR in Arabic.
  - Keyboard shortcuts.
  - The locked state.
  - Error states.
- **Integration** (`integration_test/player_test.dart`, live API, Linux and the Android emulator): launch → open a movie → play 5 s → seek → change quality → leave → resume. Then the same for an episode, with Next episode.
- **Manual before release:** a 2-hour movie in 4K on desktop, a full anime season with styled subtitles on a phone, airplane mode mid-play, and a 403 forced by editing a URL's signature in a debug build.

## 12. Not in this phase
- **Picture-in-picture:** not chosen for now. Android could add it later with a small native change. iOS PiP isn't possible with media_kit's mpv backend.
- **Casting, background audio, lock-screen controls:** later, if wanted. `audio_session` is a first step toward them.
- **Audio track switching:** every file has one audio track (API.md §3).
- **Offline playback:** Phase 6 adds `LocalSource`. The player is built for it already.
- **Long-press for 2× speed:** an idea for later.

## 13. Risks and open questions (for M0)

| Risk | Plan |
|---|---|
| Non-fast-start 1080p files start slowly (mpv must read the tail first) | Measure in M0. Tune `network-timeout`, the read-ahead and the cache. If it's still slow, show the poster behind the loader so it never looks broken |
| The hybrid subtitles don't work (subtitle text isn't sent while `sub-visibility=no`, or toggling at runtime misbehaves) | Fall back to libass for every track. The size then goes through `sub-scale`, and subtitles may be cropped in Fill mode |
| libass on desktop doesn't pick up `sub-fonts-dir` set after start | Set it before the first subtitle loads, or pass it through the mpv config folder. Linux usually has Arabic system fonts as a backup |
| 4K is too heavy for some phones (decoder or memory) | Hardware decoding by default. On decoder errors, fall back once and then offer 1080p. The always-visible chip makes the cause clear |
| Errors from mpv are strings, not codes | M0 records what a 403, a timeout and a DNS failure look like, and `media_kit_engine.dart` maps them to typed errors |
| Windows has no dev machine yet | M8 needs a Windows machine or VM. The NVIDIA Linux bug (AGENTS.md) doesn't affect Windows |
| `volume_controller` and `screen_brightness` differ between Android and iOS | Wrap them in the gesture layer only, and test both platforms when iOS starts (PLAN.md Phase 6) |

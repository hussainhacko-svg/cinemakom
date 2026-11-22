# Cinemakom on TV (Android TV / Google TV): plan

**Goal:** a TV app you can use from the sofa with only the remote (D-pad, OK, Back), where **every action on every screen can be reached and nothing traps the focus**. It is a **separate UI** (`lib/tv`) built on the same data layer as the phone and desktop app. The target is the owner's TCL Google TV.

Read with [`DESIGN.md`](DESIGN.md) (colours, type, motif) and [`PLAYER.md`](PLAYER.md) (the player this UI drives). This file replaces `ANDROID_TV.md` (*2026-11-20*).

---

## 1. Why a separate UI

The first attempt (2026-11-20, reverted the same day) patched the phone and desktop widgets with `isTv` branches. Testing it on the TV showed focus traps that made features unusable, for example **downloading one episode of a series**. The causes, which this plan is built to avoid:

| What went wrong | Rule in this plan |
|---|---|
| Arrow keys used Flutter's default *geometric* traversal (it guesses the nearest widget on screen), so focus jumped to the wrong row or couldn't reach small buttons beside big ones (an episode's download button) | Every move is declared by the screen (§5.1 R1) |
| A side rail competed with the content for Left; ~300 lines of edge heuristics in `AppShell` tried to guess when Left meant "open the rail" | Top tabs, reached with Up and Back only (§2) |
| Hidden things could take focus (9 invisible hero banners, hidden player controls) | Nothing invisible is focusable (R5) |
| Some actions only existed as long-press or hover (Remove from Continue watching) | Every action is a visible, focusable control (R6) |
| The search box grabbed focus and the arrow keys moved its cursor | Text input only on OK (R8) |
| Phone layouts at 960 × 540 dp: small text and targets, hero filling the screen | Own layouts and type sizes for 3 m away (§6) |
| The phone UI was hard to change without breaking TV, and the other way round | `lib/tv` is separate; phone and desktop code never checks `isTv` (§4.3) |
| A second UI (`lib/features/tv`, 5.6k lines) was written but never compiled or wired in, and milestones were ticked without a TV check | Each milestone ends with a check on the TV, and "done" means checked (§10) |

## 2. Decisions *(2026-11-20)*

1. **Separate TV UI in `lib/tv`**, chosen at startup when `isTv`. Phone, tablet and desktop UIs are unchanged.
2. **One APK** for phones and TVs (no separate flavor or store listing). The release workflow stays as it is.
3. **Navigation: top tabs** (Home · Search · Library · Downloads · Settings), like Google TV's own home screen. Up from the first row reaches them; Back goes there. There is no side rail.
4. **Focus look: ring plus a slight grow.** The focused card grows slightly (posters 1.05, §6.3) with a 3 px `bulb` ring; focused buttons and rows also get a `boothRaised` fill. It's a `Transform` (no shadow, blur or gradient), so DESIGN.md §6 still holds.
5. **Downloads stay on TV**, with the same rules as phones (quality asked each time, Download season, at most 2 at once).
6. **Same Marquee theme:** the same colours and fonts, with TV sizes (§6.2). Still one theme.
7. **No touch gestures, no screen lock, no brightness, no app volume on TV.** The TV's own volume keys stay with the system.
8. **No wrap-around:** pressing an arrow at the end of a row does nothing. Focus never jumps somewhere unexpected.
9. **The screens are designed** on the TV page of the "Cinemakom Design Directions" canvas (claude.ai artifact `XEb3j3VhiknZVEpX4FuLnU`, page TV): the system sheet, every screen at 960 × 540, English and Arabic. Chosen from its alternatives (*2026-11-20*): the Home hero **side by side** (not banner first), episodes in **two panes** (seasons beside episodes), and the player with **chips at the top and buttons at the bottom** (not everything at the bottom).

**Decided while building:**
- **Search keyboard** *(owner, 2026-11-20)*: the system keyboard (Gboard for TV, which has Arabic and voice) opened by OK on the search box. If it misbehaves on the TCL (it can hold the D-pad, or cover the results), build an in-app letter grid like YouTube TV afterwards.
- **Back on the Home tab bar** *(TV-2)*: exit straight away, as Google TV apps do.
- **Skip intro while the controls are hidden** *(owner, 2026-11-20)*: it takes the focus when it appears, so OK skips (Netflix does this), and so does Up next. The button says what OK will do. Up and Down still show the controls.
- **The player's preview frame** *(owner, 2026-11-20)*: the design's 99 dp height and 2 px `cream` border, at the video's shape (PLAYER.md §7.8), not a fixed 16:9.
- **The subtitles panel** *(owner, 2026-11-20)*: the choices as drawn, then a Sync row (−0.5 s · the delay · +0.5 s, and a reset). The size stays in Settings.
- **Player states without an artboard** *(owner, 2026-11-20)*: the focused seek bar, the Episodes panel, Up next, "Still watching?", the error and end screens, and "Resuming from": built from the existing TV pieces and listed in §8 for the TV check.

## 3. What exists today

**Kept from the first attempt** (the groundwork, all reviewed):
- `AndroidManifest.xml`: `LEANBACK_LAUNCHER`, `touchscreen` and `leanback` not required, `android:banner`.
- `tool/brand/generate.py` makes `drawable-xhdpi/tv_banner.png` (640 × 360).
- `MainActivity.kt`: `isTvDevice()` (TV UI mode or the leanback feature), the `io.github.sharon_xa.cinemakom/platform` channel (`isTv`), and portrait only on phones.
- `lib/core/platform/platform_info.dart`: `initPlatformInfo()` (awaited in `main`), `isTv`, `isTouchMobile`, `debugIsTvOverride`.
- `setBrowseOrientation` / `setPlayerOrientation` do nothing on TV. Settings hides Screen rotation, and downloads don't ask for the notification permission.

*Status (2026-11-20):* TV-0 to TV-3 are done and checked on the TCL: the tab shell, Home, genre pages and See all, Details with episodes, the person page and downloads. TV-4 (the player) and TV-5 (Search, Library, Downloads, Settings) are built and tested, waiting for their check on the TV; TV-6 is done except the performance run on the TCL (§10). What to check is [`TV_CHECK.md`](TV_CHECK.md).

**Problems in the groundwork, fixed in TV-0** *(code done 2026-11-20: `TvActivity`, no display-mode request on TV, the lockup banner)*:
- The manifest now says `screenOrientation="unspecified"` and `MainActivity` asks for portrait in `onCreate`. The system's starting window comes before `onCreate`, so a phone held sideways shows the splash in landscape and then flips. That's what the manifest's `portrait` was there to prevent (AGENTS.md).
- `MainActivity` asks for the display's fastest mode on every device. On a TV that can switch the HDMI output mode (a black blink, or 4K60 → another mode), so skip it on TV.
- The banner has only the mark. Google TV's guidelines want the app name on it.

**Reused as is:** everything under `lib/core` and `lib/data`, and the providers and logic of the features:
- `home_providers.dart`, `details_providers.dart`, `library_providers.dart`, `search_history.dart`, `catalog_providers.dart`
- `MediaSource` + `pagedMediaProvider` (infinite paging)
- `PlayerController`, `PlayerState`, `quality.dart`, `subtitles.dart`, `up_next.dart`, the engines, `AudioFocus`
- `DownloadsRepository`, `SearchRepository`, `LibraryRepository`, `StatusRepository`
- UI pieces with no layout opinions: `MediaImage`, `BulbLoader`, `CinemakomMark`, `errorMessage`, `context.joinMeta` / `context.isolate`, and `HeroTitle`'s fitting (with the TV size)

**Moved out of screen files in TV-0**, so `lib/tv` doesn't import phone screens:
- `staffProvider` (in `staff_screen.dart`) → `staff_providers.dart`
- `downloadOfProvider`, `progressOfProvider` and the UI-free parts of `startDownload` / `startSeasonDownload` (in `download_actions.dart`, mixed with sheets and snack bars) → `download_flow.dart`. The phone keeps its sheets and the TV gets its own panels.

## 4. Architecture

### 4.1 Entry
```dart
// main.dart
runApp(ProviderScope(retry: noRetry, child: useTvUi ? const TvApp() : const CinemakomApp()));
```
- `useTvUi` = `isTv || const bool.fromEnvironment('CINEMAKOM_TV')`. The define lets us **build the TV UI on Linux**: `fvm flutter run -d linux --dart-define=CINEMAKOM_TV=true` opens a 960 × 540 window (window_manager). The keyboard stands in for the remote: arrows, Enter = OK, Esc/Backspace = Back, Space = play/pause.
- `TvApp` is its own `MaterialApp.router` with `tvRouterProvider`, `buildMarqueeTvTheme()`, the same l10n and locale handling, and the first-launch language step. The settings, preferences and database are the same, so switching UIs on one device keeps history, favorites and downloads.

### 4.2 Folders
```
lib/tv/
  tv_app.dart              # MaterialApp.router, theme, remote key bindings
  tv_router.dart           # welcome, the tab shell, title, genre, list, person, watch
  tv_navigation.dart       # tvOpenTitle / tvOpenGenre / tvOpenList / tvOpenPerson / tvOpenPlayer
  theme/                   # MarqueeTvText (TV sizes), TvSpace (safe area, keylines), focus constants
  focus/                   # the focus system (§5): TvFocusable, TvZone, TvScreen, TvPanel, memory, scroll, watchdog
  widgets/                 # TvTabBar, TvPosterCard, TvWideCard, TvRow, TvGrid, TvButton, TvChip, TvListRow,
                           # TvSidePanel, TvChoicePanel, TvErrorView, TvEmpty
  screens/                 # welcome, home, search, library, downloads, settings, details, genre, list, person
  player/                  # tv_player_screen.dart, tv_controls.dart, tv_seek_bar.dart, panels
```

### 4.3 Boundaries
- `lib/tv` may import `lib/core`, `lib/data`, the `*_providers.dart` / flow / logic files of `lib/features`, and the shared pieces listed in §3. It never imports a phone screen or a phone widget.
- `lib/features` and `lib/app` never import `lib/tv`, and never check `isTv` for layout. (`isTouchMobile` stays for platform behaviour: orientation, notification permission.)
- `test/tv/boundaries_test.dart` reads the import lines and fails on a crossing, so this can't drift.
- New strings go in the ARB files with a `tv` prefix where the wording differs from the phone ("Press OK to type").

### 4.4 Routes
The same paths and argument classes as the phone (`TitleArgs`, `MediaListArgs`, `PersonArgs`, `PlaybackRequest`), in their own router. A `StatefulShellRoute.indexedStack` keeps one back stack per tab. Pages push inside the tab; the player pushes above the shell. On pop, focus goes back to the item that opened the page (§5.1 R2).

## 5. The focus system

This is what makes or breaks the TV app. It's built first (TV-1) and every screen uses it. No screen handles arrow keys by itself.

### 5.1 Rules
- **R1 Declared moves, no guessing.** A screen is a vertical list of **zones**. A zone is a row, a column or a grid of focusable items. Inside a zone, arrows move by index. Between zones, Up and Down go to the previous or next zone. Flutter's directional traversal is switched off in the TV app (a `TvScreen` handles the arrows, with a traversal policy that never guesses), so where focus goes depends only on the order of the zones, never on pixel positions. One kind of zone sits side by side: a **split** (two columns, used for the episodes panes), where Left and Right move between the columns and each column keeps its own memory.
- **R2 Focus memory.** Each zone remembers its last index, so Down then Up comes back to the same card. Moving between zones keeps the column where the layout lines up (an episode's play part and download button, see §7.4). Each page remembers its focus while another page is on top, and gets it back on pop.
- **R3 Edges.** An arrow at the edge of a zone does nothing (no wrap, no jump). Up from the top zone of a tab's root screen goes to the tab bar. There are two named exceptions: Left/Right at the ends of the Home hero's buttons change the banner (§7.1), and the player while its controls are hidden (§8).
- **R4 The Back ladder.** Back always does something, in this order:
  1. Close the open panel or dialog. Focus goes back to the control that opened it.
  2. On a pushed page: pop the page.
  3. On a tab's root screen with focus in the content: scroll to the top and focus that tab in the tab bar.
  4. On the tab bar, not on Home: go to Home.
  5. On the Home tab bar: exit (§2).
- **R5 Nothing hidden is focusable.** Anything invisible, faded out, collapsed or still loading is inside `ExcludeFocus`. Disabled controls are skipped by their zone but stay visible.
- **R6 No hidden actions.** Every action is a visible control you can focus. Long-press OK and the remote's menu key can be shortcuts, never the only way.
- **R7 Focus is never lost.** When the focused item goes away (a download deleted, a list refreshed, a title removed from Continue watching), focus moves to the next item, then the previous one, then the next zone. In debug builds, a watchdog (`TvFocusWatchdog`) asserts that focus never falls back to the root scope, and logs the screen and the last key. That's how a trap shows up in a test or a debug run instead of on the sofa.
- **R8 Text input only on OK.** A text field is never focused by moving through the screen. It sits behind a `TvButton` that looks like a search box. OK opens the keyboard; Done or Back closes it and returns to D-pad moves.
- **R9 Panels are modal.** Side panels and dialogs keep focus inside them (on purpose), open with the current choice focused, and close with Back.
- **R10 Scrolling follows focus.** The focused card stays fully on screen at a fixed keyline. Rows scroll so the focused card sits at the start keyline (until the row's end); the page scrolls so the focused zone sits at a fixed height. A held arrow (key repeat) jumps without animation, so holding Right through 100 posters doesn't queue 100 animations. Paged grids load the next page when focus gets within 2 rows of the end.
- **R11 Initial focus.** Each screen declares where focus starts (Home: Play on the hero; Details: Play/Resume; a panel: the current choice). Focus is never left empty after a load, a route change or an error.
- **R12 RTL.** Arrows follow what you see: in Arabic, Right moves toward the start of a row. Zones use start/end, never left/right. The player's seek bar keeps PLAYER.md §2 (always left → right, so Right always seeks forward).

### 5.2 Building blocks (`lib/tv/focus`) *(built in TV-1)*
| Widget | Job |
|---|---|
| `TvFocusable` | One focusable item at an `index` of its zone, with a `label` (its accessible name, and how tests find it): a builder gets `focused`, plus `onSelect` and an optional `onLongSelect`. It handles the arrows (always used: they never reach Flutter's traversal) and OK, and reports focus to its zone |
| `TvZone.row` / `.column` / `.grid(columns:)` | Owns the moves inside it by index (R1), skips disabled and `ExcludeFocus`ed items (R5), remembers its index (R2), and passes edge arrows to its group. `order` is its place in the screen. A row of cells (an episode's play part and download button, a Continue row's title · Details · Remove) is a grid, so Up and Down keep the cell |
| `TvGroup.split` | Zones side by side (seasons \| episodes): Left and Right move between them, each keeps its own memory, Up and Down go on to the screen |
| `TvScreen` | The ordered zones of a page (the root group), its initial focus (`TvZone(initial: true)`, R11), getting focus back when its route is current again or its content loads (R2), Back (R4) and the scroll keylines (R10, give its `ScrollController` to the page's scroll view). A screen inside another's group continues it (a tab's content under the tab bar) |
| `TvBack` | One rung of the Back ladder. `TvApp` asks them from the focused widget outwards (`tvHandleBack`); none takes it: exit. Not nested `Actions`: Flutter's `Shortcuts` stops at the nearest action even when it's disabled, so they can't fall through |
| `showTvSidePanel` | A panel that slides in from the end edge, as its own route and screen: modal, opens on its initial zone, Back closes it, focus goes back to its opener (R4, R9, R11). `showTvChoicePanel` (`widgets/`) is the picker on top of it |
| `TvFocusWatchdog` | The debug check for R7: three frames after a focus change, focus on nothing while a shown screen has something to focus is reported with the route and the last key. In a test that's a failure |

The widgets on top (`lib/tv/widgets`): `TvCardFocus` (the card look), `tvFocusRing`, `TvButton`, `TvListRow`, `TvChoicePanel`, and `TvTextEntry` (R8: a button that looks like the field; OK swaps in the `TextField`, Done or Back swaps back). Sizes are in `MarqueeTvText` and `TvSpace` (`lib/tv/theme`); `buildMarqueeTvTheme` is the one Marquee theme with them.

**Choices made while building (TV-1):**
- **OK fires when the key comes back up**, as Android TV's own buttons do. Held for 0.5 s it fires `onLongSelect` instead, and a key that comes up on another item (after the first opened something) does nothing.
- **Scrolling (R10):** a horizontal scroll view puts the focused item's edge at its zone's `keyline` (48 dp by default), until the row's end. The page puts the zone's top at 27 dp for a row (a Home row's zone includes its title, and Home uses 16 dp (`TvSpace.homeRowKeyline`), so the title, not the cards, sits there; 2026-11-21) (and for a grid's first row, so its header shows), scrolls only as far as needed further down a grid or column, and goes back to the top for the first zone. A column that scrolls by itself (the seasons) scrolls only as far as needed. A key repeat jumps.
- **Focus memory across pages (R2)** is the screen's: its root group remembers its last zone, and the screen takes focus back when its route is current again and focus is on nothing.

The remote keys are bound once, in `TvApp`'s `Shortcuts`: `select`, `enter`, `numpadEnter` and `gameButtonA` → activate (outside a `TvFocusable`, which reads OK itself); `escape` (and Backspace, gamepad B) → back. *Found on the TCL (TV-2):* Android delivers the remote's Back twice, as a `goBack` key and as the system Back (`popRoute`), so from See all one press popped the page and then left the app. The remote's Back now comes in once, as the system Back: `TvApp` is a `WidgetsBindingObserver` ahead of the router's, its `didPopRoute` runs the ladder, and the app always tells Android it handles Back itself (`setFrameworkHandlesBack(true)`), so Android never closes it on its own. Tested with `binding.handlePopRoute()`. The arrows are not bound at all, so Flutter never guesses. Media keys go to the player. *Checked in TV-0:* Flutter 3.47.9 already maps `select` to activate on Android, but `TvApp` passes its own complete map (`tvShortcuts` in `lib/tv/tv_keys.dart`), so nothing depends on Flutter's defaults. Space and the media keys (play/pause, play, pause, rewind, fast forward, next) map to `TvMediaIntent`, which `TvApp` hands to `TvMedia.handler`: the open player's, so they work over its panels too (TV-4). Backspace and gamepad B also mean Back.

### 5.3 Proving there are no traps
- **`TvDriver`** (`test/tv/tv_driver.dart`) presses keys in widget tests: `right()`, `down()`, `ok()`, `back()`, `focused` (the focused item's semantics label), `focusPath`. **After every press it checks the focus ring is drawn whole** (`expectRingVisible`, `test/tv/ring_check.dart`): inside the screen and inside every scroll view and clip above it, with the card's grow included. A list clips its own edges, so a list of rows or buttons leaves the ring's width (3 dp, or a button's 5) of room on every side. Rings cut that way were seen on the TCL: the search box, the Continue watching cards, the Sort panel's rows (2026-11-21/22). Only the demo screen opts out (`checkRings: false`).
- **`expectNoTraps`** (`test/tv/reachability.dart`) is the reachability check below; `test/tv/focus_rules_test.dart` runs it and a test per rule on `test/tv/demo_screen.dart` (every kind of zone, a panel, a pushed page, a text entry).
- **A reachability test for every screen**, with fixture data (`fixtureApi()`), in English and in Arabic. Starting from the initial focus, it tries every arrow from every item it reaches (a breadth-first search over focus states). It checks that:
  1. every enabled control on the screen was reached (from the semantics tree: every button has a label);
  2. pressing Back repeatedly from any reached item leaves the screen;
  3. the watchdog never fired.
- **Scenario tests** for the things that broke before, each with keys only:
  - download episode 3 of season 2 of a series, pause it, resume it, delete it
  - Download season
  - play an episode, change subtitles and quality, open the episodes panel, play the next one, go back
  - remove a title from Continue watching
  - search, open a result, go back to the results with the same item focused
  - change the language to Arabic in Settings, with focus kept on the language row

A new screen isn't done until its reachability test passes.

## 6. Visual design for TV

### 6.1 The canvas
- Android TV draws apps at **960 × 540 dp** (1080p at 2×), also on 4K panels. Design and test at that size.
- **Safe area** (overscan): 48 dp at the start and end, 27 dp at the top and bottom (Google's 5%). Nothing focusable goes outside it. Rows may scroll under the edge.
- One screen = one or two zones of real content, plus a peek of the next. Rows are kept short (no 30-item header bars).

### 6.2 Type and size (`MarqueeTvText`)
The phone sizes are too small at 3 m. Starting values, to tune on the TV in TV-2:

| Style | Phone | TV |
|---|---|---|
| `heroTitle` | 58 | 52 (with `HeroTitle`'s steps) |
| `displayLarge` | 40 | 40 |
| `sectionTitle` | 22 | 24 |
| `title` | 16 | 18 |
| `body` | 15 | 17 |
| `label` | 14 | 16 |
| `caption` | 12 | 14 |
| `navLabel` (tab bar) | 11 | 16 |

The fonts and the Arabic rules (no tracking, no uppercase, taller line heights) are the same as DESIGN.md §2. Focusable items are at least 48 dp tall.

### 6.3 Focus look
- **Cards** (posters, wide cards, cast): scale over 150 ms ease-out, with a **3 px `bulb` ring** at the card's radius. **Posters** (every poster card and See all, in rows and grids) scale to **1.05**, one value for all of them (`TvFocusStyle.posterScale`; 1.08 looked too big in Favorites, owner 2026-11-22). **Cast** photos scale to **1.08** (`cardScale`). **Wide cards** (Continue watching, 300 wide) scale to **1.04** (`TvFocusStyle.wideCardScale`): at 1.08 they reached 18 px past their sides, under the next card, and their top was cut (seen on the TCL, 2026-11-21). Each card has its own `RepaintBoundary`, so growing one doesn't repaint the row. Rows leave enough room between and above cards for the grown card and its ring (`TvCardFocus.reach`, checked in `test/tv/card_room_test.dart`).
- **Buttons, chips, list rows, tabs:** a `boothRaised` fill and a 3 px `bulb` ring. The primary (`bulb`) button gets a `cream` ring, so it shows against its own fill. **Focus and selection never change a label's weight** (owner, 2026-11-22): every TV label keeps one weight, so nothing resizes or moves. Focus shows as the fill and the ring; the current tab, chip or segment as its colour and fill.
- Nothing else is dimmed (no opacity over images, DESIGN.md §6). Selected and focused look different: a selected chip has the phone's selected style; focus adds the ring.
- `disableAnimations`: no grow animation (the ring and fill still show).

### 6.4 Tab bar
At the top, inside the safe area: the mark at the start, then Home · Search · Library · Downloads · Settings. The current tab has a `boothRaised` pill and a `bulb` label; the focused tab adds the ring. Moving onto a tab switches to it (like Google TV); Down enters that tab's content where it was left. The tab bar scrolls away with the page and comes back with Up from the top zone or with Back. *Built (TV-2):* `TvShell` and `TvTabBar`. The bar shows on a tab's own screen while focus is on it or on the page's first zone; further down it slides up (150 ms) and the page gets the screen. Pushed pages (a genre, See all) have no bar, as in the Genre design. Pages change without a transition (cheap on slow chips, easy to follow), and go_router's `requestFocus` is off, so a route change never takes focus to its scope.

## 7. Screens

Each screen lists its zones from top to bottom. ⟵⟶ is a row, ↕ a column, ▦ a grid.

### 7.1 Home
```
 ▸ Home  Search  Library  Downloads  Settings                [mark]
 NOW SHOWING                                ┌────────────────────────┐
 THE TITLE, FITTED                          │   banner cover 2.7:1   │
 2023 · Drama · 2h                          └────────────────────────┘
 [ ▶ Play ] [ ⊡ Favorite ]                       • • ● • • • • • • •
 Continue watching
 [▣ wide][▣ wide][▣ wide][▣ wide] →
 Latest movies
 [▯][▯][▯][▯][▯][▯][▯][See all]
```
- Zones: hero buttons ⟵⟶ · Continue watching ⟵⟶ · one zone per row ⟵⟶.
- **The hero:** text at the start, the banner beside it (always side by side on TV). Left from Play shows the previous banner and Right from Favorite the next one (R3's exception), with the bulb pager showing where you are. Auto-advance (10 s) pauses while the hero has focus.
- **Rows:** the header isn't focusable; **See all** is the last card of the row. Continue cards are wide (16:9 artwork if the title has it, else the poster with the text beside it), with the progress bar. Removing one is in the Library (§7.5).
- Initial focus: Play.
- *Offline (TV-6):* when the banners fail, the hero says why, with Try again where Play would be (focus starts there). When the API's own rows fail, one row says so, with Try again; the other rows already had theirs. Tested with every request failing, no traps.
- *Built (TV-2):* `lib/tv/screens/home`. While the hero loads, focus waits on the Home tab and moves to Play when it arrives, unless a key was pressed meanwhile. The next and previous banners load hidden, so a change shows at once; banners loop, like the phone's. Continue cards are the poster beside the text (300 × 117), because history keeps no 16:9 artwork. Rows build lazily, with a 600 px cache, so the next row is always built before focus can move to it.

### 7.2 Genre page and full lists
- Zones: the filter chips ⟵⟶ (Sort · Kind · Language; each opens a `TvChoicePanel`) · the grid ▦ (6 posters per row at 960 dp).
- Infinite paging through `pagedMediaProvider` (R10 loads ahead). The grid shows a placeholder row while a page loads; placeholders aren't focusable (R5).
- A failed page shows a focusable "Try again" in place of the next row.
- *Built (TV-2):* `lib/tv/screens/browse`, with `TvPagedGrid`. The title and the chips share the first line (the Genre design); focus starts on the first poster. Kind is Movies or Series only: the genre API needs one. The audio languages and sort labels come from `genre_providers.dart`, shared with the phone.

### 7.3 Details
```
 ┌──────┐  THE TITLE
 │poster│  2021 · Action · 2h 10m · Arabic, English
 │      │  Synopsis, 3 lines…
 └──────┘  [ ▶ Resume S2 E5 ] [ ⇩ Download season ] [ ⊡ Favorite ] [ ▷ Trailer ]
 EPISODES
  Season 1        03  Episode 3 · watched           [ ✓ ]
 ▸Season 2        04  Episode 4 · watched           [ ⇩ ]
  Season 3        05  Episode 5 · 14 min left ▬▬──  [42%]
  Season 4        06  Episode 6                     [ ⇩ ]  ← focused
  Season 5        07  Episode 7                     [ ⇩ ]
 Cast and crew   [◯][◯][◯][◯] →
 More like this  [▯][▯][▯][▯][▯] →
```
- Zones: actions ⟵⟶ · the episodes **split** (seasons ↕ | episodes ↕) · cast ⟵⟶ · more like this ⟵⟶.
- **The split:** moving onto a season shows its episodes (no OK needed); Right goes to the episodes at the remembered one (else the one playing or watched last); Left from an episode's play cell goes back to the selected season. Down from the last episode or the last season goes to Cast and crew; Up from the first goes to the actions.
- **Long seasons** (more than 50 episodes): the blocks of 50 are entries in the seasons column, under their season ("Season 1", then "1–50", "51–100", …). A one-season show like One Piece lists only the blocks. The column scrolls on its own.
- Genres are part of the meta line, not focusable (one less zone). The IMDb link isn't shown: TVs have no browser.
- Movies: Download in the actions row. Series: **Download season 3** is the first row of the episodes pane (TV-3, after the TCL check); each episode has its own button.
- Trailer opens the YouTube app on the TV (`url_launcher` with the YouTube TV intent). If no app can take it, the button isn't shown.
- Initial focus: Play/Resume. Opening from Continue watching opens on that episode's season and block.
- *Built (TV-3):* `lib/tv/screens/details`. The episode selection (season, blocks of 50, the anchor episode) is `episode_view.dart` and the Play/Resume target `play_target.dart`, both shared with the phone. The two panes are 360 dp tall and scroll by themselves; their zones align the whole split under the EPISODES heading (`TvZone(pageWhole: true)`). A series downloads a season from its episodes pane: "Download season 3" is the pane's first row, one Up from the first episode (in the actions row it could only be reached by going up through the seasons, which picked Season 1; found on the TCL). The panes leave 8 dp beside their lists for the focus ring, which the lists clip. Cast photos are 96 dp circles that grow on focus; a person opens `lib/tv/screens/person` (photo, name, role · count, a 6-column grid).

### 7.4 Episodes and downloads (the trap that broke before)
- **Each episode row is a row of two cells** (inside the episodes column of the split): the episode itself (OK plays it) and its download button. Up and Down keep the cell: on the download button of episode 3, Down goes to the download button of episode 4 (R2's column memory). So a whole season can be downloaded one by one going down a single column.
- The download button shows the state: ⇩ (not downloaded), a progress ring with the percentage, ✓ (done), or an error mark.
- OK on ⇩ opens a `TvChoicePanel` "Download in…" with each quality and its size (as on the phone, asked each time). OK starts it; the panel closes and focus is back on the same button, now showing progress.
- OK on a download in progress opens a panel: Pause or Resume, Cancel (asks first), Go to Downloads. OK on ✓: Play, Delete (asks first).
- Download season opens the same quality panel, then queues the season's episodes (at most 2 run at once, like the phone).
- Low storage: before starting, compare the size with the free space (TVs often have about 4 GB free). If it doesn't fit, say so in the panel instead of starting.
- *Built (TV-3, owner's choice 2026-11-20: check on TV):* `lib/tv/widgets/tv_downloads.dart`. Free space comes from `StatFs` (`freeBytes` on the platform channel, `downloadFreeSpaceProvider`); a quality fits when it leaves the engine's 500 MB reserve (`downloadSpaceReserveMb`). The panel shows "x GB free on this TV", a quality that doesn't fit stays visible as "Too big · size" and is skipped, and when none fits the TV says "Not enough space on this device" instead of an empty panel. Cancel and Delete ask first and open on the safe answer. While the qualities load, the button shows the bulbs. The download engine starts in `TvApp`, as in the phone app.

### 7.5 Library
- Zones: the segment ⟵⟶ (Continue watching · Favorites) · the list ↕.
- **Continue watching** is a list of rows, each a row of cells: the title (OK resumes) · Details · Remove. Remove hides the title the same way as the phone (`continue_hidden`). Focus then moves to the next row (R7).
- **Favorites** is a grid ▦. OK opens Details; removing is the Favorite button on Details.

### 7.6 Search
- Zones: the search box (a `TvButton`, R8) · kind chips ⟵⟶ (All · Movies · Series) · results ▦ (or recent searches ↕, then the genre grid ▦, before anything is typed). There is no People row: the API has no people search (DESIGN.md §8).
- OK on the box opens the system keyboard (§2). Results update as you type (the same 400 ms debounce and search as the phone). Done or Back closes the keyboard; then Down enters the results.
- Recent searches: each row is a row of cells: the search (OK runs it) · ✕. "Clear all" is at the end of the list.
- Coming back from a result focuses the same result.

### 7.7 Downloads
- Zones: the storage line (not focusable) · the list ↕.
- Each row is a row of cells: the title (OK plays when done, or opens the series' episodes) · Pause/Resume · Delete. A series is one row; OK opens its episodes as the same kind of list.
- Empty state: text plus a focusable "Browse Home" button.

*Built (TV-5, code 2026-11-20; not yet checked on the TV), §7.5–7.8:* `lib/tv/screens/{search,library,downloads,settings}`, with the shared rows in `lib/tv/widgets/tv_shelf.dart` (`TvShelfRow`, `TvTile`, `TvSegment`, `TvSettingsRow`, `TvEmpty`).
- **Search** follows the Search designs. Moving onto the box shows "OK to type", and OK opens the TV's keyboard (owner's choice; the letter grid comes only if Gboard misbehaves on the TCL). Results update as you type. Opening a result remembers the search, and Back returns focus to that result. `TvPagedGrid` gained a `filter` for the kind chips; a filtered grid with fewer than two rows loads more pages by itself, since paging otherwise starts only when focus nears the end. **Left out from the Results design:** the People row and the "4 people" count, because the API has no people search (§7.6).
- **Library** follows its design. Moving onto a segment shows it, as with the tabs. After Remove, focus stays on the row that moves up into its place.
- **Downloads** follows its design, except the storage bar: it says what downloads use and what's free on the TV (`downloadFreeSpaceProvider`) instead, as the phone dropped its bar. On a row still downloading, OK opens the title's Details. A series' row opens its episodes (`/downloads/saved/:id`, `TvSavedSeriesScreen`). Cancel and Delete ask first.
- **Settings** has the groups of the phone (General, Playback, Help), where the design says App, Playback, About. Subtitle size is here (owner's choice). Report a bug and Cinemakom on GitHub open a panel of QR codes to scan with a phone (`showTvQrPanel`; TVs rarely have a mail app or a browser): email and GitHub's bug form, both filled in with the version and the TV's model. About and licenses opens `TvLicensesScreen`: one row per package, and the licence in a panel scrolled with Up and Down. Flutter's own licences page can't be used with a remote. The labels moved to `lib/features/settings/settings_labels.dart`, shared with the phone.
- *Found while building:* a page pushed inside a tab must use `TvScreen(order: 1)`, its slot in the shell, as Details does. With the default 0 it sat beside the tab bar, so Back focused the tabs instead of the row that opened the page.

### 7.8 Settings and first launch
- Settings is a column ↕ of rows (Language, Default quality, Default subtitles, Downloads storage info, About/licenses). OK opens a `TvChoicePanel` with the current value focused. Changing the language rebuilds the app in RTL or LTR and keeps the focus on the Language row.
- First launch: two large buttons, English and العربية, with English focused. OK picks one and opens Home.

## 8. Player on TV

`TvPlayerScreen` drives the same `PlayerController` and engine as the phone (ExoPlayer on Android TV, with audio focus and wakelock). It has its own controls and no gestures. PLAYER.md §6 (playback flow, recovery) and §7 (features) apply as written.

### 8.1 Controls hidden (watching)
| Key | Does |
|---|---|
| OK | Pause and show the controls with Play/Pause focused. When **Skip intro** or **Up next** is showing, it has the focus and OK activates it (§2) |
| Left / Right | Seek −10 / +10 s. Held: 10 s steps, then 30 s after 2 s, then 60 s after 5 s. Shows the seek bar with the preview frame and the target time; it plays from there 600 ms after the last key |
| Up / Down | Show the controls (Play/Pause focused) |
| Back | Save the position and leave the player |
| Play/pause, Play, Pause, Rewind, Fast forward, Next | Always work, controls shown or not |

### 8.2 Controls shown
```
  THE TITLE · S2 E3                         [Subtitles: Arabic] [1080p] [1×] [Fit]
  ───────────────●───────────────────────────────────  41:02 / 58:30
            [ ⏮ −10 ] [ ▶ ] [ +10 ⏭ ]        [ Episodes ] [ Next episode ]
```
- Zones: chips ⟵⟶ (top) · seek bar · buttons ⟵⟶ (bottom). Initial focus: Play/Pause.
- **Seek bar:** focusable. Left/Right scrub with the preview frame and the same speed-up; OK or 600 ms without a key plays from there; Up/Down leave it without seeking.
- **Chips** open `TvChoicePanel`s (quality, subtitles with "Arabic (styled)" where the engine supports it, speed, fit) with the current choice focused. **Episodes** opens a side panel with season chips and the episode list (the block logic from Details).
- The controls hide after 5 s without a key. Back hides them first; a second Back leaves.
- Errors, "Still watching?", Up next and the end screen show focused buttons (Try again, Back, Play next). Focus is never left on a hidden control (R5).

*Built (TV-4, code 2026-11-20; not yet checked on the TV):* `lib/tv/player` (`tv_player_screen.dart`, `tv_player_controls.dart`, `tv_seek.dart`, `tv_player_panels.dart`), from the Controls, Watching and Subtitles artboards. How it works:
- **Focus:** with the controls hidden, the video itself is one focusable item ("Video"); it reads the arrows through `TvFocusable.onKey`. The controls are rebuilt each time they show, and Play/Pause takes focus with `TvFocusable.autofocus`. While an autofocus is pending, nothing else moves focus (`tvAutofocusPending`). Hidden controls are inside `ExcludeFocus` (R5).
- **Seeking:** `TvScrub` holds the target; the video moves 600 ms after the last key, or on OK. A held key steps 10 s, then 30 s after 2 s, then 60 s after 5 s; a new press starts again at 10 s. Back cancels a seek in progress. OK on the seek bar with no seek in progress plays or pauses.
- **Shared with the phone:** the labels moved to `lib/features/player/player_labels.dart` (`formatClock`, `speedLabel`, `fitLabel`, `subtitleLabel`, `delayLabel`). `SeekPreviewFrame` and `SubtitleLayer` are shared too (the layer got `liftedBy`, because the TV's bottom controls are taller).
- **Episodes panel:** Details' `TvEpisodes` with `downloads: false`, opened on the episode playing, which is marked "Playing" on `boothRaised`. The panel is 620 wide.

Differences from the artboards, for the TV check:
- The subtitles panel lists Off first (PLAYER.md §7.2's order); the artboard has it last. Sync is below the tracks (owner's choice).
- **No artboard yet**, built from the system sheet's pieces:
  - the focused seek bar (the thumb grows to 20 with a `cream` ring, like the `bulb` button's);
  - the Up next card (`booth`, at most 480 wide, an 88 × 50 image, Play now and Hide, a `bulb` line that fills during the countdown; it says "Still watching?" when asking). *On TV it shows only for the countdown, the last 10 s (or once the file ended), not from the "watched" point like the phone, so it doesn't cover the credits (owner, 2026-11-21); Next episode in the controls works before that;*
  - "Resuming from 14:32" and Start over (a pill above the bar);
  - the failure screen (the message, then Try again focused and Back; Back alone when there are no streams);
  - the notes for a lowered quality or failed subtitles (a `booth` pill at the top for 4 s; the phone uses a snack bar).
- The ±10 s buttons use the Material replay arrow with "10" under it, close to the artboard's own drawing.

### 8.3 TV specifics
- No app volume: the system handles the remote's volume keys.
- 4K: TVs decode HEVC and H.264 in hardware through ExoPlayer. Check frame times and memory with 4K on the TCL (TV-4).
- Later, not in v1: matching the TV's refresh rate to the video (24p) through ExoPlayer's frame-rate support.

## 9. Performance

- TV UIs run at **60 Hz**, so the frame budget is 16.7 ms, but TV chips are much slower than phones. Budget for a low-end quad-core with 2 GB of RAM.
- Images: see §9.1. Artwork has to look sharp on a 4K panel, and that's a goal, not a nice-to-have.
- Rows: `ListView.builder` with a fixed `itemExtent` (DESIGN.md §6). A held arrow jumps without animation (R10).
- Grow animation: `Transform.scale` inside a `RepaintBoundary`, never a layout change.
- The player overlay doesn't repaint the video: it's above the texture, behind its own `RepaintBoundary`.
- Measure on the TV: `integration_test/tv_perf_test.dart` (holding Right along a Home row, Down through Home, then the 4K player: controls up, fading, watching, a held seek over the video, a panel, paused; and memory) with `flutter drive --profile` over network adb (the command is in AGENTS.md; it reports against 60 Hz itself, and `--dart-define=PERF_QUALITY=1080` compares with 1080p). Under the test binding the app draws ~60 frames a second even when paused, so its player numbers are a worst case. **For video smoothness, measure the real app** with `tool/tv_cadence.sh <tv-ip:port>` while it plays: the screen refreshes between frames from SurfaceFlinger. A 24 fps film on 60 Hz is a mix of 2× and 3×; 4× is a video frame held too long (a hitch).
- **TVs draw with Skia, not Impeller** (`MainActivity.getFlutterShellArgs`, phones keep Impeller). *Measured on the TCL 2026-11-21:* with Impeller (Vulkan), 4K showed 2–8 hitches every 4 s, from the cost of compositing each 4K frame on the MediaTek MT5896; with Skia, about one every 9 s. Skia was also faster on Home (raster 4.4 ms against 6.6 ms holding Right) and over 4K with the controls fading (9.5% of frames late against 44%) or a panel open (3% against 53%). 1080p was smooth on both. Impeller's OpenGL backend (`ImpellerBackend=opengles`) was ignored by this engine: it stayed on Vulkan. Flutter plans to remove the Skia opt-out: **re-measure with `tool/tv_cadence.sh` when upgrading Flutter**. Skia can show a one-time hitch the first time something new is drawn (shader compilation; seen once on the first held seek).
- *Measured on the TCL 2026-11-21 (Skia):* memory 613 MB with 4K, 544 MB with 1080p. The TV has one display mode (3840×2160 at 60 Hz, no 24 Hz), so films always show the 2×/3× cadence, as in every app on it. The app draws ~30 frames a second while playing and none when paused.

### 9.1 Sharp artwork on a 4K TV
The first TV test showed soft, blurry posters. There are three causes, and each has a fix:

1. **The source is too small.** Cards on phones use `imgMediumThumbObjUrl`, which is **293 px wide** (API.md, Images). A focused TV poster is about 130 dp wide. That's 260 px if the TV draws its UI at 1080p and 520 px if it draws at 4K. Even a 1080p UI gets stretched 2× by the TV to fill the panel, so a 293 px poster looks soft either way. **On TV, cards use the original upload** (`imgObjUrl`, which is `MediaItem.hdPosterUrl`). Most are 1000–2000 px wide, but some are as small as 253 px, so take whichever of the two is larger. The Details poster and the cast photos follow the same rule.
2. **The decode size.** Decode at the size the card reaches *when focused*, in real pixels: `memCacheWidth = card width × 1.08 × MediaQuery.devicePixelRatio`, rounded up, never more than the source. Use the TV's measured pixel ratio, not a fixed 2×. The first attempt multiplied the ratio by 2 again ("because the TV upscales"), so a 2× TV decoded at 4× and wasted memory. The upscaling is real, but it works on the finished 1080p frame: an image can't carry more detail than the frame it's drawn into, so decoding past the real pixel ratio adds nothing you can see. If the TV draws apps at 4K, the ratio is already 4 and the formula gives the full size by itself. Hero banners (covers up to 4050 × 1500) decode at the banner width × the pixel ratio.
3. **The scaling filter.** TV cards use `FilterQuality.medium`, so a large original scaled down to the card, and the 1.08 grow, stay smooth instead of jagged. Phones keep `low`.

**Loading:** show the 293 px thumbnail at once (it's small and loads fast), then swap in the original for the cards on screen once scrolling stops (about 250 ms), with no fade and no layout shift. Originals can be 1.5–2.5 MB each, so fetching them for every card in every row would make Home crawl on TV Wi-Fi. Only cards that are actually on screen get the big image, and the image cache keeps them on disk. The focused card gets its original first.

**Memory:** a focused poster decoded at a 2× ratio is about 280 × 420 px (≈ 0.5 MB). At 4× it's about 560 × 840 px (≈ 1.9 MB). Size `imageCache.maximumSizeBytes` from the measured ratio and the TV's RAM: start at 150 MB at 2× and 250 MB at 4×. Then check memory while scrolling all of Home (TV-6).

**Measure first (TV-0):** on the TCL, record `adb shell wm size`, `adb shell wm density` and the app's `MediaQuery.devicePixelRatio` and `MediaQuery.sizeOf`. That shows whether the app draws at 1080p or at 4K, and settles the numbers above.

**Measured on the TCL (2026-11-20):** a TCL Smart TV Pro, Android 14 (API 34), **32-bit only** (`armeabi-v7a`), 2.4 GB of RAM, 46 GB free. The panel is 3840 × 2160 with one display mode (4K60, HDR), but `wm size` overrides it to **1920 × 1080** at density 320, so the app draws at **960 × 540 dp, ratio 2** (`MediaQuery` agrees). So: decode at ratio 2, start the image cache at 150 MB, and a 4K stream plays at 1080p sharpness (accepted in v1, "Video too" below). Install `app-armeabi-v7a-release.apk` on it.

**Video too:** if the TV draws apps at 1080p, a 4K stream drawn through a Flutter texture (how `ExoPlayerEngine` draws) is scaled down to 1080p before the TV stretches it back up, so it looks like 1080p. The platform-view mode (a `SurfaceView`) that would keep 4K was rejected in PLAYER.md decision 7: Flutter draws it above every widget, so the controls only showed on the letterbox bars. TV-0's measurement says whether this applies. If it does, v1 accepts it (4K still plays, at 1080p sharpness).

## 10. Milestones

| | Scope | Done when |
|---|---|---|
| **TV-0** ✅ | Groundwork fixes (§3): phone splash upright again (manifest back to `portrait`, plus a `TvActivity` subclass declared `landscape` with only `LEANBACK_LAUNCHER`, and `android.hardware.screen.portrait` not required); no display-mode request on TV; banner with the name (generator); the `CINEMAKOM_TV` define and a placeholder `TvApp`; move `staffProvider` and the download flow out of screen files; the boundaries test; the remote key bindings; measure the TCL's UI resolution and pixel ratio (§9.1) | The phone starts upright even held sideways. The TV shows the banner and opens the placeholder in landscape. `--dart-define=CINEMAKOM_TV=true` runs on Linux. Analyze and tests clean. *Checked 2026-11-20 on the TCL (banner, landscape start, arrows, OK, Back exits) and the phone (upright when started sideways)* |
| **TV-1** ✅ | The focus system (§5.2), `TvDriver`, the reachability test helper, the watchdog, `MarqueeTvText`, `TvSpace`, the focus look, `TvSidePanel` / `TvChoicePanel` | Unit tests for R1–R12 on a demo screen pass, in English and Arabic. *Done 2026-11-20: 16 tests in `focus_rules_test.dart`, with the no-trap check in both languages and a test that the watchdog fires* |
| **TV-2** ✅ | Shell and tab bar, Back ladder, first launch, Home (hero, rows, Continue watching, See all), genre page and lists, sharp artwork (§9.1: original images, decode size, filter, the thumbnail-then-original swap) | Reachability tests pass. **On the TV:** browse Home to a list and back with no trap; tune the type sizes; posters and the hero look sharp on the 4K panel from close up. *Checked 2026-11-20 on the TCL by the owner: Home, tabs, Back, See all and genre pages; a See all grid that never scrolled was fixed (the first-zone scroll rule now applies to its first row only)* |
| **TV-3** ✅ | Details: actions, seasons, ranges, episodes, cast, more like this, person page; the TV download panels (§7.4) | The episode download scenario passes in tests. **On the TV:** download, pause, resume and delete an episode, and Download season. *Checked 2026-11-20 on the TCL by the owner: Details, seasons and blocks, the episode download panels, Download season (moved into the episodes pane), cast and the person page, Trailer* |
| **TV-4** | The TV player (§8): controls, seek bar with previews and speed-up, panels, episodes panel, skip intro, up next, errors | Player scenarios pass with `FakeEngine`. **On the TV:** a movie and a series in 1080p and 4K, every control by remote, frame times and memory. *Code and tests done 2026-11-20 (`test/tv/tv_player_test.dart`, no traps in English and Arabic). On the TCL 2026-11-21/22: frame times and memory measured (§9, Skia on TVs), most of the player checked; fixed from the check: the controls fade (it never ran), Up next (only the last 10 s, smaller), no weight change on focus, Android subtitle markup. Left (2026-11-22): the Arabic lines in TV_CHECK.md §1 and §4, a download played offline (§6), and Back/OK while seeking (§2, partly checked)* |
| **TV-5** | Search (decide the keyboard), Library, Downloads, Settings | Reachability tests for every screen. **On the TV:** the §11 checklist, in English and Arabic. *Code and tests done 2026-11-20 (`test/tv/tv_tabs_test.dart`: no traps on every tab in English and Arabic, plus the search, remove-from-Continue, downloads and language scenarios). Search checked on the TCL 2026-11-22 (Gboard works: no letter grid needed); fixed: the search box ring. Library, Downloads and Settings checked on the TCL 2026-11-22. Fixed from the check: posters grow 5% (`TvFocusStyle.posterScale`, one value for all), failed downloads have Details, Settings → Help has Report a bug and GitHub (QR codes), a panel no longer moves the page, a page's end shows whole, and a download no longer sticks at 99% (DOWNLOADS.md rule 4). Left: holding an arrow down Home (TV_CHECK.md §12)* |
| **TV-6** | Polish: the performance test on the TV, low storage, offline, error states, `tv_screenshots_test.dart` at 960 × 540, docs (PLAN.md, DESIGN.md, AGENTS.md) | The §11 checklist passes on the TCL with a release APK. *Done without the TV (2026-11-20): `tv_screenshots_test.dart` (run on Linux, both languages), `tv_perf_test.dart` (dry-run on Linux), offline Home, the docs. Low storage was done in TV-3. The performance test ran on the TCL 2026-11-21 (§9). Home fixes from the check: Continue watching cards (grow 4%, 20 dp apart), row titles 16 dp from the top. Left: offline Home (TV_CHECK.md §13)* |

Each milestone is committed on its own, and only ticked in PLAN.md after its TV check.

## 11. Checklist on the TV (release APK)

The step-by-step check for TV-4 and TV-5 is [`TV_CHECK.md`](TV_CHECK.md).


- Install: `adb connect <tv-ip>:<port>` (Developer options → Wireless debugging; the port changes each time it's turned on). Check `adb shell getprop ro.product.cpu.abilist`: many TVs run 32-bit Android on a 64-bit chip, and then they need `app-armeabi-v7a-release.apk`.
- The banner on the home screen; opens straight into landscape; Home's first focus is Play.
- Every tab with only the remote: in, around, out with Back, and the app exits from the Home tab bar.
- Details of a long series (One Piece): the range chips, download an episode in the middle of a block, Download season, pause, resume, delete.
- Player: OK, Left/Right held, the seek bar with previews, every chip panel, the episodes panel, skip intro, up next, Back; 1080p and 4K; subtitle size readable from the sofa.
- Search with the TV keyboard, in Arabic too; open a result and come back.
- Library: remove from Continue watching; Favorites.
- Settings: switch to Arabic and check every screen in RTL.
- Offline: unplug the network, play a download, see the error screens' Try again.
- Holding an arrow along a long row and down Home stays smooth.
- Artwork is sharp on the 4K panel: posters (focused and not), the hero banner, the Details poster and cast photos. Look from up close and compare with the Google TV home screen. A 4K stream plays smoothly (if the TV draws apps at 1080p it looks like 1080p, §9.1, video).

## 12. Risks

| Risk | Plan |
|---|---|
| Flutter's `TextField` with Gboard for TV (the keyboard may hold the D-pad or cover the results) | Try it first in TV-5; fall back to an in-app letter grid |
| Remotes without media keys | Everything works with D-pad, OK and Back; media keys are extras |
| Small storage on TVs | The free-space check before every download (§7.4) |
| Slow TV chips | §9, and measure in TV-4 and TV-6 instead of guessing |
| 32-bit TVs | Ship and test `armeabi-v7a` (the release already builds it) |
| HDMI mode switches | No display-mode request on TV (TV-0) |
| Soft artwork on 4K (seen in the first test) | §9.1: originals on TV, decode at the focused size × the real pixel ratio, `FilterQuality.medium`, measured on the TCL in TV-0 |
| 4K video scaled down to a 1080p UI | Measured in TV-0; accepted in v1. The `SurfaceView` fix failed with our overlay (PLAYER.md decision 7, §9.1) |
| Two UIs drifting apart in behaviour | They share the providers and repositories; only widgets are separate. The boundaries test keeps them apart |

# TV check: TV-4 and TV-5

What to try on the TCL before TV-4 and TV-5 are ticked in `TV.md` §10 and `PLAN.md`. Each line says what to do and what should happen. Note what's wrong next to it (or tell Claude), then tick the milestone.

**Install:** turn on wireless debugging on the TV and note its port (it changes each time), `adb connect 192.168.0.145:<port>`, then `adb install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (`-r` keeps the app's data). Rebuild first if `main` moved on: `fvm flutter build apk --release --split-per-abi --target-platform android-arm`.

Do the whole list in English, then switch to Arabic in Settings and repeat the parts marked **(AR)**.

---

## 1. Player: controls shown (TV-4)

Start a movie from Details (Play), and an episode from a series.

- [x] It opens with the controls up and **Play/Pause focused** (a `cream` ring around the `bulb` circle).
- [x] The top shows the title (and "Season 2 · Episode 5" for an episode) at the start, and the chips at the end: subtitles, quality, speed, fit.
- [x] **Up** from Play/Pause → the seek bar (the thumb grows, with a `cream` ring) → Up again → the chips. **Down** comes back the same way.
- [x] **Left/Right** along the bottom: −10, Play/Pause, +10, then Episodes and Next episode (series only). At the ends nothing happens.
- [x] −10 and +10 jump back and forward 10 s.
- [x] The controls **hide after 5 s** without a key while playing, and stay while paused.
- [x] **Back** with the controls up hides them; a second Back leaves the player. Back in Details shows Resume at the right time.
- [ ] **(AR)** The chips and the Episodes/Next buttons swap sides; the seek bar, the times and −10 · ▶ · +10 keep their places (Right is always forward).

## 2. Player: seeking

- [x] With the controls hidden, **Right** once: a `bulb` "+0:10" pill and the frame over the bar (if the title has previews), "18:52 · was 18:42" under it, and the video jumps there about half a second after you let go.
- [x] **Hold Right**: steps of 10 s, then 30 s after 2 s, then 60 s after 5 s. It stays smooth, with no backlog after you let go.
- [-] While seeking, **Back** cancels (the video stays where it was); **OK** jumps at once.
- [x] The preview frame has the **video's shape** (try a wide film, e.g. Avengers: Endgame: not squashed).
- [x] On the **seek bar** (controls up): Left/Right scrub, OK jumps, Up/Down leave without seeking.
- [x] OK on the seek bar with nothing pending plays/pauses (an extra: say if it surprises you).

## 3. Player: OK, Up/Down, media keys

- [x] Controls hidden: **OK** pauses and shows the controls (Play focused). **Up or Down** shows them without pausing.
- [x] The remote's **play/pause** key works with the controls up, hidden, and with a panel open. Rewind/fast forward (if the remote has them) step 10 s; Next plays the next episode.
- [x] The TV's **volume** keys change the TV's volume (the app doesn't touch them).

## 4. Player: panels

- [x] **Subtitles** chip: a panel at the end edge over the still-playing video, opened on the current track (✓). Rows: Off, Arabic, English (Off is first; the artboard had it last: say which you prefer).
- [x] With a track on: **Sync** −, the value, +, Reset. Each press moves 0.5 s and the panel stays open; Reset is skipped at 0. Picking a track closes the panel.
- [x] **Quality**, **Speed**, **Fit** panels open on the current choice; picking one applies it (quality keeps the position) and focus returns to that chip, which shows the new value.
- [x] **Back** closes any panel, focus back on its chip.
- [ ] **(AR)** The panels come from the left, and the text reads right to left.

## 5. Player: series

- [x] **Episodes**: a wide panel with seasons beside episodes, opened on the episode playing (`boothRaised`, "Playing" in `bulb`). Left to the seasons; moving onto a season shows its episodes; OK on an episode plays it in place (quality, subtitles and speed kept).
- [x] A long series (One Piece): the blocks of 50 are in the seasons column, and it opens on the right block.
- [x] **Next episode** plays the next one; it's skipped on the last episode.
- [x] The **Up next** card appears only in the **last 10 s** (smaller since 2026-11-21: judge the look): with the controls hidden it **takes the focus** (OK plays now, Right → Hide, Up/Down show the controls). A `bulb` line fills and the next episode starts.
- [x] After 3 automatic episodes: "Still watching?" with Play now focused.

## 6. Player: Skip intro, resume, errors

- [x] An episode with an intro: **Skip intro** appears above the bar; with the controls hidden it **takes the focus**, so OK skips. Left/Right still seek from it. After 8 s it shows only with the controls.
- [x] Resuming a title watched before: "Resuming from 14:32" for 5 s, with **Start over** in the row above the bar when the controls are up.
- [x] **No network** (unplug or Wi-Fi off) mid-play: "Reconnecting…", then it plays on, or the error with **Try again focused** and Back.
- [ ] A downloaded episode plays **offline**.

## 7. Player: picture and performance

- [x] A **1080p** and a **4K** title play smoothly (4K looks like 1080p: expected, `TV.md` §9.1).
- [x] The controls fade in and out without stutter over 4K.
- [x] **Subtitles are readable from the sofa** at Medium; Small and Large (Settings) change them. They move up when the controls show.
- [x] Measured 2026-11-21 (`TV.md` §9): TVs now draw with Skia, which removed most 4K hitches. Say if anything still feels slow, or if something stutters the first time it appears.
- [x] Each subtitle line shows **once**. (On Linux, in the live screenshot run, one Arabic line was drawn twice; it may be the subtitle file or mpv, but check on the TV.)

## 8. Search (TV-5)

- [x] Down from the Search tab focuses the **search box** ("OK to type" in `bulb`); the arrows never type.
- [x] **OK opens the TV's keyboard** (Gboard). Type: results appear as you type. Check that Gboard doesn't capture the D-pad or cover the results so you can't use them. **If it does, say so: the fallback is an in-app letter grid.**
- [x] Voice typing from Gboard works (if offered). **(AR)** Arabic typing works.
- [x] Done (or Back) closes the keyboard, focus on the box; Down → All · Movies · Series → the results.
- [x] The kind chips filter the results.
- [x] Open a result, press Back: **the same result is focused**. The search is now under Recent searches.
- [x] Before typing: **Recent searches** (OK searches again; ✕ removes one, Down keeps the ✕ column), **Clear all**, then the genre tiles (OK opens the genre).
- [x] No People row (the API can't search people; the artboard had one).

## 9. Library

- [ ] Down from the tab → the **Continue watching · Favorites** segment; moving onto Favorites shows them (no OK needed).
- [ ] Continue rows: **OK resumes**, **Details** opens the title, **Remove** hides it and focus stays on the row that moved up (on the last row: the one above).
- [ ] Down keeps the column (Remove → Remove).
- [ ] Favorites: a grid of posters; OK opens Details. Empty shelves say what goes there.

## 10. Downloads

- [ ] The top line: "4.0 GB used by Cinemakom" and "3.5 GB free on this TV" (no storage bar: the artboard had one).
- [ ] A running download: "42% · 1080p · 3.2 MB/s · 4 min left" and a `bulb` bar; **Pause** → Resume; **Cancel** asks first, opening on "Keep downloading".
- [ ] A finished movie: OK plays it; **Delete** asks first ("Keep it" focused).
- [ ] A series: one row "3 episodes · 1.8 GB" with a chevron; OK opens its episodes (OK plays one, Delete each, Delete all episodes at the bottom); Back comes back to the series row.
- [ ] Nothing downloaded: the message and **Browse Home**.

## 11. Settings

- [ ] Rows: Language, Default quality, Default subtitles, Subtitle size, About and licenses. Groups are General · Playback · Help (the artboard says App · Playback · About: say which you prefer).
- [ ] OK opens a panel on the current value; picking saves it.
- [ ] **Language → العربية**: the app flips to RTL at once and focus stays on the Language row. Then do the **(AR)** checks above, and switch back.
- [ ] **About and licenses**: a list of packages; OK shows a licence, Up/Down scroll it, Back closes.

## 12. Everywhere

- [ ] No focus trap anywhere: every button can be reached, and Back always does something (panel → page → tab bar → Home → exit).
- [ ] Focus is never lost (nothing focused after a load, a delete or a removal).
- [ ] Holding an arrow along a row and down Home stays smooth.
- [ ] **Focus rings are never cut** (fixed 2026-11-22; the tests now check every ring): on a genre page, open Sort, Kind and Audio and move through every row; the ring shows whole on all four sides. Same in the other panels (player quality, speed, fit, subtitles with Sync and Reset; Settings; downloads) and on every screen.

## 13. TV-6, with the TV connected to this machine

- [ ] **Offline Home:** turn Wi-Fi off and open the app. The hero says there's no connection, with **Try again focused**; the rows say so too. Wi-Fi back on, Try again loads them.
- [x] **Performance** (Claude runs it over adb; it uninstalls the app at the end, wiping its data): `fvm flutter drive --profile --no-dds -d 192.168.0.145:<port> --driver=test_driver/perf_driver.dart --target=integration_test/tv_perf_test.dart`. *Run 2026-11-21: led to Skia on TVs; the numbers are in `TV.md` §9.* For video smoothness, `tool/tv_cadence.sh 192.168.0.145:<port>` while something plays.

When everything passes, tick TV-4 and TV-5 in `TV.md` §10 and in `PLAN.md`.

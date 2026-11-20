# TV check: TV-4 and TV-5

What to try on the TCL before TV-4 and TV-5 are ticked in `TV.md` §10 and `PLAN.md`. Each line says what to do and what should happen. Note what's wrong next to it (or tell Claude), then tick the milestone.

**Install:** `adb connect 192.168.0.145:5555`, then `adb install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (`-r` keeps the app's data). Rebuild first if `main` moved on: `fvm flutter build apk --release --split-per-abi`.

Do the whole list in English, then switch to Arabic in Settings and repeat the parts marked **(AR)**.

---

## 1. Player: controls shown (TV-4)

Start a movie from Details (Play), and an episode from a series.

- [ ] It opens with the controls up and **Play/Pause focused** (a `cream` ring around the `bulb` circle).
- [ ] The top shows the title (and "Season 2 · Episode 5" for an episode) at the start, and the chips at the end: subtitles, quality, speed, fit.
- [ ] **Up** from Play/Pause → the seek bar (the thumb grows, with a `cream` ring) → Up again → the chips. **Down** comes back the same way.
- [ ] **Left/Right** along the bottom: −10, Play/Pause, +10, then Episodes and Next episode (series only). At the ends nothing happens.
- [ ] −10 and +10 jump back and forward 10 s.
- [ ] The controls **hide after 5 s** without a key while playing, and stay while paused.
- [ ] **Back** with the controls up hides them; a second Back leaves the player. Back in Details shows Resume at the right time.
- [ ] **(AR)** The chips and the Episodes/Next buttons swap sides; the seek bar, the times and −10 · ▶ · +10 keep their places (Right is always forward).

## 2. Player: seeking

- [ ] With the controls hidden, **Right** once: a `bulb` "+0:10" pill and the frame over the bar (if the title has previews), "18:52 · was 18:42" under it, and the video jumps there about half a second after you let go.
- [ ] **Hold Right**: steps of 10 s, then 30 s after 2 s, then 60 s after 5 s. It stays smooth, with no backlog after you let go.
- [ ] While seeking, **Back** cancels (the video stays where it was); **OK** jumps at once.
- [ ] The preview frame has the **video's shape** (try a wide film, e.g. Avengers: Endgame: not squashed).
- [ ] On the **seek bar** (controls up): Left/Right scrub, OK jumps, Up/Down leave without seeking.
- [ ] OK on the seek bar with nothing pending plays/pauses (an extra: say if it surprises you).

## 3. Player: OK, Up/Down, media keys

- [ ] Controls hidden: **OK** pauses and shows the controls (Play focused). **Up or Down** shows them without pausing.
- [ ] The remote's **play/pause** key works with the controls up, hidden, and with a panel open. Rewind/fast forward (if the remote has them) step 10 s; Next plays the next episode.
- [ ] The TV's **volume** keys change the TV's volume (the app doesn't touch them).

## 4. Player: panels

- [ ] **Subtitles** chip: a panel at the end edge over the still-playing video, opened on the current track (✓). Rows: Off, Arabic, English (Off is first; the artboard had it last: say which you prefer).
- [ ] With a track on: **Sync** −, the value, +, Reset. Each press moves 0.5 s and the panel stays open; Reset is skipped at 0. Picking a track closes the panel.
- [ ] **Quality**, **Speed**, **Fit** panels open on the current choice; picking one applies it (quality keeps the position) and focus returns to that chip, which shows the new value.
- [ ] **Back** closes any panel, focus back on its chip.
- [ ] **(AR)** The panels come from the left, and the text reads right to left.

## 5. Player: series

- [ ] **Episodes**: a wide panel with seasons beside episodes, opened on the episode playing (`boothRaised`, "Playing" in `bulb`). Left to the seasons; moving onto a season shows its episodes; OK on an episode plays it in place (quality, subtitles and speed kept).
- [ ] A long series (One Piece): the blocks of 50 are in the seasons column, and it opens on the right block.
- [ ] **Next episode** plays the next one; it's skipped on the last episode.
- [ ] Near the end, the **Up next** card (no artboard: judge the look): with the controls hidden it **takes the focus** (OK plays now, Right → Hide, Up/Down show the controls). In the last 10 s a `bulb` line fills and the next episode starts.
- [ ] After 3 automatic episodes: "Still watching?" with Play now focused.

## 6. Player: Skip intro, resume, errors

- [ ] An episode with an intro: **Skip intro** appears above the bar; with the controls hidden it **takes the focus**, so OK skips. Left/Right still seek from it. After 8 s it shows only with the controls.
- [ ] Resuming a title watched before: "Resuming from 14:32" for 5 s, with **Start over** in the row above the bar when the controls are up.
- [ ] **No network** (unplug or Wi-Fi off) mid-play: "Reconnecting…", then it plays on, or the error with **Try again focused** and Back.
- [ ] A downloaded episode plays **offline**.

## 7. Player: picture and performance

- [ ] A **1080p** and a **4K** title play smoothly (4K looks like 1080p: expected, `TV.md` §9.1).
- [ ] The controls fade in and out without stutter over 4K.
- [ ] **Subtitles are readable from the sofa** at Medium; Small and Large (Settings) change them. They move up when the controls show.
- [ ] Not measured yet: frame times and memory with 4K (`TV.md` TV-4). Say if anything feels slow.

## 8. Search (TV-5)

- [ ] Down from the Search tab focuses the **search box** ("OK to type" in `bulb`); the arrows never type.
- [ ] **OK opens the TV's keyboard** (Gboard). Type: results appear as you type. Check that Gboard doesn't capture the D-pad or cover the results so you can't use them. **If it does, say so: the fallback is an in-app letter grid.**
- [ ] Voice typing from Gboard works (if offered). **(AR)** Arabic typing works.
- [ ] Done (or Back) closes the keyboard, focus on the box; Down → All · Movies · Series → the results.
- [ ] The kind chips filter the results.
- [ ] Open a result, press Back: **the same result is focused**. The search is now under Recent searches.
- [ ] Before typing: **Recent searches** (OK searches again; ✕ removes one, Down keeps the ✕ column), **Clear all**, then the genre tiles (OK opens the genre).
- [ ] No People row (the API can't search people; the artboard had one).

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

When everything passes, tick TV-4 and TV-5 in `TV.md` §10 and in `PLAN.md`.

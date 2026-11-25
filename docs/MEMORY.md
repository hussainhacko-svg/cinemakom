# Memory: the investigation and fix plan

> **Status (2026-11-25):** M0 done (the measuring tools). M1, the investigation, is next. Work through §5 in order and tick each box as it's done, with the date and the numbers. **Read it before changing caches, buffers, or how the player opens and closes.**

The goal: **memory comes back when a feature is done with it, and stays flat over a long session.** Closing the player returns the app to about what it used before the video. Ten videos in a row use no more than one. Browsing for an hour levels off. This matters most on the weakest devices we support: low-end phones and TVs with 1.5 to 2 GB of RAM, where Android kills the app in the background, or the TV stutters, long before a desktop notices.

## 1. What the owner saw (2026-11-25, Omarchy laptop, AppImage, mpv engine)

1. **Fresh start: about 250 MB.** While browsing it climbs slowly: 259, then the 260s.
2. **About 850 MB while a 4K video plays.** That could be reasonable (§3.1).
3. **After the video closes, the 850 MB stays.** It doesn't drop back towards 250.
4. Not checked yet: phones and TVs (ExoPlayer, a different engine), and Windows (mpv).

## 2. What "fixed" means (targets)

Set the real numbers in M1 from what we measure; these are where to start.

| # | Target | Measured how |
|---|---|---|
| T1 | **Closing the player gives memory back:** 30 s after closing, RSS is within **+60 MB** of before the video opened | The cycle test (§4.1) |
| T2 | **No leak across videos:** after 10 open, play, close cycles, RSS after the 10th close is within **+20 MB** of after the 1st | The cycle test |
| T3 | **Browsing levels off:** scrolling all of Home and 3 genre pages, then idling 10 minutes, rises less than **+10 MB** in the last 5 minutes | The browse test (§4.2) |
| T4 | **4K playback stays bounded:** RSS over 20 minutes of 4K doesn't keep rising after the first 2 minutes | The long-play test (§4.3) |
| T5 | **Budgets per device:** while playing 4K, phone and TV stay under the numbers set in M1 (TV.md §9 measured 613 MB on the TCL) | The perf tests (`player_perf_test`, `tv_perf_test`) |

## 3. Suspects (what's known before measuring)

None of these is confirmed. M1 decides which are real.

### 3.1 Desktop player (mpv, `media_kit_engine.dart`)
- **The read-ahead buffer is 192 MB on desktop** (`_bufferBytes`, 64 MB on mobile), plus `cache-secs` 60 and `cache-on-disk`. Up to 192 MB of the 850 MB can be this, by design.
- **Decoded 4K frames:** about 12 MB each (NV12), and mpv queues several, plus GPU copy-back (`vaapi-copy`) and the texture media_kit draws into.
- **Freed but not returned:** closing calls `player.dispose()` (`_release`), and a test checks no native player stays alive (`livePlayers`). But glibc keeps freed memory in its per-thread arenas for reuse, and mpv and FFmpeg use many threads. RSS would then stay high without a leak. The next video reuses it.
- **media_kit_video's texture and GL objects** (`NativeVideoController`): whether they are freed on dispose is unverified.

### 3.2 Phone and TV player (ExoPlayer, `exo_player_engine.dart`)
- Different engine, so nothing in §3.1 carries over. ExoPlayer's own buffer, MediaCodec's output surfaces, and video_player's texture. Android splits memory into Java heap, native, and graphics (`dumpsys meminfo`). Each needs its own check.

### 3.3 Images
- **Phone and desktop use Flutter's default image cache** (up to 100 MB, 1000 images). Nothing sets it. That may be the slow climb in §1.1. It should level off at the cap.
- **The TV sets 150 MB at 2× and 250 MB at 4×** (`TvImage.sizeCache`, TV.md §9.1): *above* the default, on the weakest devices. Plus `hdUrl` originals on focus.
- **Decoded posters stay cached while a video plays.** They aren't needed then, and they compete with the player for RAM.
- `MediaImage` decodes at display width (`memCacheWidth`), which keeps each image small. Check that every image path uses it (seek previews, hero banners, the TV's HD swap).

### 3.4 Dart side
- Providers kept alive (14 files use `keepAlive` or `autoDispose`): a page's provider that never disposes, or a family that grows with every title opened.
- Streams, controllers, listeners and timers not cancelled when a screen or the player closes (`Timer.periodic` in `player_controller.dart` and `diagnostics.dart`).
- `EventLog` and other in-memory buffers: check they are capped.

### 3.5 Downloads
- A long download (GBs) shouldn't hold growing buffers in memory. Unchecked.

## 4. How we measure

### 4.1 The cycle test (new: `integration_test/memory_test.dart`)
Through the real app and engine, live API:
1. Open the app, settle, record **before**.
2. Repeat 10 times: open a 4K title, play 60 s, record **playing**; close, wait 30 s, record **after close #n**.
3. Report each step as JSON (`test_driver/perf_driver.dart`, like the perf tests).

Each record: `ProcessInfo.currentRss`, Dart heap used and capacity (VM service `getMemoryUsage`, profile mode), `MediaKitEngine.livePlayers`, the image cache's `currentSizeBytes` and `liveImageCount`. On Linux add `/proc/self/smaps_rollup` (anonymous vs file-backed). On Android add `dumpsys meminfo <package>` (Java, native, graphics) from the driver side.

Run on: Linux (this PC), the Omarchy laptop, the phone (`flutter drive --profile`), the TCL TV, Windows if available.

### 4.2 The browse test
Scroll all of Home, open 3 genre pages and scroll each 10 pages, open 10 titles, then idle 10 minutes. Record every 30 s. Phone, desktop and TV.

### 4.3 The long-play test
20 minutes of 4K, RSS every 30 s. Includes a few seeks and a quality switch. Phone, desktop and TV.

### 4.4 Telling a leak from held memory
- **Grows every cycle:** a leak. Find which side: if Dart heap grows, take two heap snapshots (DevTools) and diff them. If only native grows, look at the engine (mpv handles, textures, ExoPlayer instances).
- **Rises on the first cycle, then flat:** held memory. On Linux, check by calling `malloc_trim(0)` after close: if RSS then drops, it's the allocator, not a leak.

### 4.5 In the field
`logEvent('memory', …)` with RSS when the player opens and 30 s after it closes, so the Activity log (Settings → Help) shows the pattern on a user's device. Twice per video, not every second.

## 5. Milestones

Each milestone ends with its numbers written here, and the plan corrected if a suspect turns out wrong.

### M0: Measuring tools
- [x] `integration_test/memory_test.dart`: the cycle test (§4.1), with the browse (§4.2) and long-play (§4.3) scenarios selectable by `--dart-define` (`MEMORY_SCENARIO`, `CYCLES`, `PLAY_SECONDS`, `LONG_MINUTES`, `IDLE_MINUTES`, `MEMORY_QUALITY`). Phone and TV UIs, as the device has it *(2026-11-25)*
- [x] The driver (`test_driver/memory_driver.dart`) writes each run's JSON to `build/memory/<device>-<ui>-<scenario>.json` and prints its table *(2026-11-25)*
- [x] A small summary script (`tool/memory_report.dart`): every sample, the peak, and PASS/FAIL against T1–T4 *(2026-11-25)*
- [x] Memory lines in the event log (§4.5): `MemoryLog` in `lib/core/diagnostics/memory.dart`, called by `PlayerController` when it opens, after 60 s of playback, when it closes, and 30 s later (that timer only once `startDiagnostics` ran, so no test is left with one) *(2026-11-25)*
- [x] AGENTS.md Commands: how to run it on Linux, the phone and the TV *(2026-11-25)*

*What the tools read (`readMemory`):* RSS and its peak (every platform); anonymous and file-backed parts (`/proc/self/smaps_rollup`, Linux and Android; what's left of RSS is shared memory, such as GPU buffers); the Dart heap, reserved heap and external memory (the app's own VM service, profile and debug builds, after a forced GC on the "closed" samples); the image cache; live mpv players; on Android `Debug.MemoryInfo` (Java heap, native, graphics, total PSS) through MainActivity's `memoryStats`.

*Smoke run (2026-11-25, this PC, EndeavourOS, NVIDIA, 2 cycles of 15 s):* start 570 MB, playing 1140 and 1165, closed 783 and 788. So +213 MB stays after the first close (T1 fails), and the second video added only +5 (T2 passes). Only a hint: M1 runs the full 10 cycles.

### M1: Investigation (every platform, every suspect)
Linux (this PC, and the Omarchy laptop):
- [ ] Cycle test: before, playing, after each close (T1, T2)
- [ ] Is the after-close memory the allocator? `malloc_trim(0)` experiment (§4.4)
- [ ] How much of the 4K peak is the 192 MB buffer? Run at 64 MB and compare
- [ ] Browse test (T3): does the idle climb level off at the image cache's cap?
- [ ] Long-play test (T4)

Android phone (ExoPlayer):
- [ ] Cycle test, with `dumpsys meminfo` (Java, native, graphics) per step
- [ ] Browse test
- [ ] Long-play test

TV (TCL, ExoPlayer, Skia):
- [ ] Cycle test, with `dumpsys meminfo`
- [ ] Browse test, with the 150/250 MB image cache, and again with Flutter's default, to compare
- [ ] Long-play test

Windows (mpv), if a machine is available:
- [ ] Cycle test

Dart side, on any platform:
- [ ] Heap snapshots before the first video and after the 10th close: list what grew
- [ ] Providers, listeners and timers that outlive their screen (§3.4)
- [ ] EventLog and other buffers are capped
- [ ] A long download: memory over 10 minutes (§3.5)

Close the milestone:
- [ ] Write the findings into §3 (confirmed or ruled out) and the targets into §2
- [ ] Decide which of the M2 items to do, and add any new ones

### M2: Fixes (only those M1 justifies)
- [ ] Leaks found in M1, each fixed, with a test that would catch it again
- [ ] Linux: give freed memory back after the player closes (`malloc_trim`, via FFI in `media_kit_engine.dart`), if M1 shows it's the allocator
- [ ] Desktop read-ahead buffer: size it from what M1 shows playback needs
- [ ] Image cache: a cap for phones and desktop, and a lower one for the TV, if the browse test shows it's needed
- [ ] Free decoded posters while a video plays (`imageCache.clear()` on opening the player) if it helps phones and TVs without slowing the return to the page
- [ ] Android: anything ExoPlayer keeps after dispose

### M3: Proof
- [ ] Every M1 test run again on each platform, the results in a table here, against T1–T5
- [ ] The owner checks on the Omarchy laptop: the app's memory drops after closing a 4K video
- [ ] The owner checks on the phone and the TV
- [ ] PLAYER.md and TV.md updated with any changed buffer or cache size, and their reasons

## 6. Risks
- **RSS isn't everything.** GPU memory on desktop (NVIDIA) may not show in RSS, and on Android graphics memory is separate. Record what each platform can see, and say what it can't.
- **The test binding draws more frames than the real app** (TV.md §9). Memory is less affected than frame times, but confirm the headline numbers in the real app with the Activity log lines (§4.5).
- **Shrinking buffers trades memory for smoothness.** Any buffer change re-runs the player perf tests and `tool/tv_cadence.sh`.

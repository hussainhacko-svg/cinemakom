# Downloads Fix — Code Review TODO

> Reviewed on `downloads-fix` at commit `255aa72` (covers `18f8499..255aa72`) against `docs/DOWNLOADS.md` and `background_downloader-9.6.6`.

---

## Critical

- [x] **1. Stop `DownloadsJanitor` from deleting user-renamed or prior-install videos in public folders** *(fixed 2026-11-22: only a failed row's leftover video and subtitles are removed; tests for renamed, unclaimed, size-mismatch and no-rows cases)*
  - **Where:** `lib/data/repositories/downloads_janitor.dart` (`sweep`, lines 152–183)
  - **Problem:** `sweep()` recursively scans `downloadRoots` (`Movies/Cinemakom` on Android, `~/Videos/Cinemakom` on desktop) and deletes any video file not in `completeVideos`/`inProgressVideos`, plus any `complete` video whose size differs from `d.totalBytes`.
    - Renaming a finished file inside `Movies/Cinemakom` (allowed by Rule 8 / §5.8) causes the janitor to permanently delete it on the next reconcile.
    - Clearing app data on Android (same UID) or reinstalling on desktop / Android 7–10 wipes all previously downloaded videos in `Movies/Cinemakom` / `~/Videos/Cinemakom`.
  - **Fix:** Never sweep unknown video files inside public user-owned folders (`Movies/Cinemakom`, `~/Videos/Cinemakom`). Only delete files explicitly owned by failed/cancelled/incomplete rows (or inside app-private legacy `Android/data/<pkg>/files/Downloads`), and do not delete a `complete` row's file on size mismatch.
  - **Test:** Add janitor unit tests verifying renamed/untracked videos in a public root are never deleted and a `complete` row's file is preserved.

- [ ] **2. Stop `DownloadsJanitor._sweepTempFiles` from deleting active and `waitingToRetry` `.partial` files**
  - **Where:** `lib/data/repositories/downloads_janitor.dart` (`_sweepTempFiles`, lines 247–319), `lib/core/downloads/background_file_downloader.dart` (line 126)
  - **Problem:** `_sweepTempFiles()` only counts `status == running` for `runningCount` and only checks `canResume` on `paused`/`failed`:
    - `TaskStatus.waitingToRetry` maps to `DownloadStatus.queued`; while waiting up to 512 s to retry from its partial file (`retries: 10`), any sweep deletes its `.partial` file.
    - When Episode 1 finishes (`_complete()` → `_sweep()`), Android's native holding queue starts Episode 3 and creates its `.partial` file before Dart processes Episode 3's `running` event; `runningCount` undercounts by 1 and deletes a live episode's temp file.
  - **Fix:** Account for `queued` rows (including `waitingToRetry` and holding-queue handoff): keep recent temp files while any `running` or `queued` row exists, and keep temp slots for tasks waiting to retry.
  - **Test:** Add janitor & repository tests covering `queued`/`waitingToRetry` temp files and holding-queue handoff during `_complete()`.

- [ ] **3. Fix `BackgroundFileDownloader.known()` overwriting `paused` tasks as `queued`**
  - **Where:** `lib/core/downloads/background_file_downloader.dart` (`known`, lines 253–265)
  - **Problem:** `_fd.allTasks(allGroups: true)` in `background_downloader-9.6.6` (`base_downloader.dart:537`, `native_downloader.dart:308`) explicitly includes paused tasks (`getPausedTasks()`). Overwriting `existing.state == DownloaderState.paused` with `DownloaderState.queued`:
    - Flips *"Waiting for connection"* (`paused`, `pausedByUser: false`) rows back to `queued` on reconcile, breaking auto-resume when network returns.
    - Prevents `_onStallGuard()` (`downloads_repository.dart:309–314`) from ever firing on a stalled paused task because it sees `state == DownloaderState.queued`.
  - **Fix:** Only insert `DownloaderState.queued` from `allTasks()` when `existing == null`; never overwrite an existing `paused` record.
  - **Test:** Add tests verifying paused tasks stay `paused` through `known()` + `reconcile()`, *"Waiting for connection"* survives reconcile and auto-resumes, and the 60 s stall guard fires when the engine remains paused.

- [ ] **4. Handle Android notification Pause, Resume, and Cancel actions properly**
  - **Where:** `lib/data/repositories/downloads_repository.dart` (`_reconcile` lines 608–619, `_onEvent` lines 1214–1358)
  - **Problem:** `background_downloader`'s `NotificationReceiver` executes Pause/Resume/Cancel natively without going through `DownloadsRepository`:
    - **Notification Pause:** `_pendingUserPause` and `d.pausedByUser` are both false, so `_onEvent(DownloaderState.paused)` treats it as a WorkManager time-limit pause, keeps the row showing *"Downloading"*, arms the 60 s guard, and turns the user's paused download into *"Stopped: interrupted"*.
    - **Notification Resume (after in-app pause):** `d.pausedByUser` stays `true`, so `_onEvent(DownloaderProgress)`, `_onEvent(DownloaderState.running)`, and `_reconcile()` ignore all progress and running updates (reproducing Original Bug #1: stuck on *"Paused"* while downloading).
    - **Notification Cancel:** `_onEvent(DownloaderState.canceled)` leaves the DB row stuck in `running`/`queued` until the next `reconcile()` turns it into *"Stopped: interrupted"*.
  - **Fix:**
    - Track internal cancels (`_pendingInternalCancel`) so external `DownloaderState.canceled` events delete the row and clean up files.
    - Limit ignoring `DownloaderProgress` after an in-app `pause()` to a short grace window (e.g. 2–3 s) instead of forever while `pausedByUser == true`, and let explicit `DownloaderState.running` / sustained progress transition a notification-resumed task back to `running`.
    - Handle unexpected `DownloaderState.paused` cleanly: wait briefly (e.g. a few seconds) for an auto-resume if a timeout ever occurred, then settle to `paused` (user-resumable) rather than falsely marking a notification-paused download as `failed (interrupted)`.
  - **Test:** Add repository tests simulating native notification Pause, Resume (from `pausedByUser: true`), and Cancel events.

---

## High

- [ ] **5. Harden `ConnectivityStreamHandler` and connectivity auto-resume**
  - **Where:** `android/app/src/main/kotlin/io/github/sharon_xa/cinemakom/MainActivity.kt` (lines 169–221), `lib/data/repositories/downloads_repository.dart` (`_onConnectivity`, lines 370–412)
  - **Problems:**
    1. Requiring `NET_CAPABILITY_VALIDATED` relies on Google's connectivity probe, which can false-offline users on Iraqi ISP / Shabakaty local routing, VPNs, or captive/local networks even when Cinemana CDN is reachable.
    2. `lastOnline` is mutated across binder threads and main thread without synchronization, and a queued `mainHandler.post { events.success(...) }` can fire after `onCancel()`.
    3. Reading `cm.activeNetwork` synchronously inside `onLost(network)` can still see the just-lost network; conversely, calling `_resume()` immediately on `onAvailable` before DNS is ready can fail `_media.streams()` and permanently convert *"Waiting for connection"* to `failed (network)`.
    4. In `_onConnectivity(false)`, if `_downloader.pause()` returns `false` on a `running` task, the DB switches to `paused` while the engine task keeps running uncanceled.
  - **Fix:**
    - Check `NET_CAPABILITY_INTERNET` (without requiring `NET_CAPABILITY_VALIDATED`), serialize state + sink checks on `mainHandler` with a nullable active sink cleared in `onCancel`, and debounce offline/online transitions briefly (e.g. 1–2 s).
    - On `onAvailable`, if `_media.streams()` fails transiently during automatic resume, keep the row in *"Waiting for connection"* and retry with short backoff instead of failing immediately.
    - If `pause()` returns `false` for a `running` task during offline transition, cancel or leave state accurate rather than desyncing DB from engine.
  - **Test:** Add repository tests for transient stream-fetch error on network return and failed `pause()` on offline drop.

- [ ] **6. Check free space and pass file sizes for season downloads**
  - **Where:** `lib/features/downloads/download_actions.dart` (`startSeasonDownload`, lines 84–120), `lib/data/repositories/downloads_repository.dart` (`downloadEpisodes`, lines 785–808)
  - **Problem:** `startSeasonDownload` skips `downloadSpaceDeficit`, and `downloadEpisodes` calls `download()` without `bytes`, leaving `totalBytes: null` at enqueue time so season episode notifications omit file sizes (including on completion).
  - **Fix:** Check estimated free space (`picked.bytes * unqueuedCount`) before starting, and pass per-episode `bytes` (e.g., `contentLength` or `picked.bytes` for the first episode).
  - **Test:** Add widget/repository tests verifying season free-space check and `totalBytes` population.

- [ ] **7. Guard and tighten `_reconcile` on-disk completion safety net**
  - **Where:** `lib/data/repositories/downloads_repository.dart` (`_reconcile`, lines 520–530)
  - **Problem:** When `row.totalBytes == null`, any non-empty file at `videoPath` (including a half-written copy) satisfies `size > 0 && row.totalBytes == null` and is marked `complete`. Also `videoFile.lengthSync()` is outside `try / on FileSystemException`, so a concurrent delete aborts the whole reconcile loop.
  - **Fix:** Wrap file stat calls in `try / on FileSystemException`, and only auto-complete from disk when `row.totalBytes != null && size == row.totalBytes`.
  - **Test:** Add reconcile test verifying an unknown-size partial file is not marked `complete`.

- [ ] **8. Fix `redownload()`, quality-switch (`switchTo`), and `_resume()` restart edge cases**
  - **Where:** `lib/data/repositories/downloads_repository.dart` (lines 991–1099), `lib/features/downloads/downloads_screen.dart` (line 352), `lib/features/downloads/download_actions.dart` (line 194), `lib/tv/screens/downloads/tv_downloads_screen.dart` (lines 323, 449), `lib/tv/widgets/tv_downloads.dart` (line 289)
  - **Problems:**
    1. `redownload()` overwrites `status = failed` before calling `_resume()`, and every UI caller ignores the returned `ResumeOutcome` — if the quality is gone (`ResumeQualityGone`), tapping **Download again** silently leaves a failed row with no prompt.
    2. `redownload()` passes `forceRestart: true`, setting `startedOver = true` (*"Started over"*) on a fresh re-download, doesn't re-fetch deleted subtitles until after completion, and skips the free-space check.
    3. `_resume(..., switchTo: fallback)` keeps the old `fileName` (e.g. `Movie 1080p.mp4` for `720p`) and old `totalBytes` (wrong progress bar and notification size).
    4. `_resume()` restart path (lines 1062–1076) does not call `_sweep()` before enqueueing, leaving orphaned temp files on disk until the next reconcile (Rule 1).
  - **Fix:**
    - Route `redownload()` through UI helpers (like `resumeDownload` / `tvResumeDownload`) that handle `ResumeQualityGone` and check free space, don't mark fresh redownloads as `startedOver`, re-save missing subtitles, and keep the row intact if quality-gone prompt is cancelled.
    - On `switchTo`, recompute `fileName` (with `uniqueFileStem`), update `totalBytes` (fetch `contentLength` or clear to `null` so it doesn't show the old size), and check free space.
    - Call `_sweep()` before re-enqueueing on restart fallback.
  - **Test:** Add unit + widget tests for `redownload()` with `ResumeQualityGone`, `switchTo` filename/size update, and restart cleanup.

---

## Medium

- [ ] **9. Fix `StatFs` failing on fresh installs before `Movies/Cinemakom` exists**
  - **Where:** `android/app/src/main/kotlin/io/github/sharon_xa/cinemakom/MainActivity.kt` (`freeBytes`, lines 65–71)
  - **Problem:** `StatFs(path)` throws `IllegalArgumentException` if `/storage/emulated/0/Movies/Cinemakom` has not been created yet, returning `null` and disabling the pre-enqueue free-space check on the very first download.
  - **Fix:** Walk up `File(path)` to the first existing ancestor directory before calling `StatFs`.

- [ ] **10. Close per-task notification gaps against `docs/DOWNLOADS.md §5.9`**
  - **Where:** `lib/data/repositories/downloads_repository.dart` (`_taskNotice`, lines 829–859), `lib/core/downloads/background_file_downloader.dart` (lines 181–214)
  - **Problems:**
    - `DownloadTaskNotice.errorBody` is static at enqueue time (`"Download failed"`), so failed notifications never show the specific failure reason (e.g. *"Storage full: 12 GB more needed"*).
    - `DownloadNotices.waiting` (`noticeWaitingSlot` in both ARBs) is currently unused dead code.
    - `BackgroundFileDownloader.resume(taskId, url)` after a cold app restart does not re-apply `configureNotificationForTask`, so resumed tasks lose their per-task size/quality text and fall back to the global template.
  - **Fix:** Re-apply `configureNotificationForTask` in `resume()` (pass `DownloadTaskNotice?` or rebuild on resume), update/show failure notification text when a task fails (if supported by `background_downloader`), and either wire `waiting` or remove the dead field if `background_downloader` has no holding-queue notification hook.

- [ ] **11. Finish Phase 6 legacy migration & janitor roots**
  - **Where:** `lib/data/repositories/downloads_repository.dart` (`start` lines 347–358, `_sweep` lines 416–429), `lib/data/repositories/download_paths.dart` (`migrateLegacyDownloads`, lines 188–269)
  - **Problems:**
    - Unfinished Phase 6 rows still point to `Android/data/<pkg>/files/Downloads` instead of restarting into `Movies/Cinemakom` (§5.6).
    - `_sweep()` doesn't include `legacyAndroidDownloadRoot()` (leaving old Phase 6 half-written files uncleaned) and passes empty `downloadRoots` on iOS (`applicationDocuments` instead of `root`).
  - **Fix:** Migrate/restart unfinished Phase 6 rows into the new root on first start, include `legacyAndroidDownloadRoot()` in `_sweep()` (where orphan cleanup is safe since it's app-private), and resolve iOS `applicationDocuments/Downloads` for subtitle/empty-dir cleanup.

- [ ] **12. Request `WRITE_EXTERNAL_STORAGE` on Android 7–9 (API 24–28)**
  - **Where:** `android/app/src/main/kotlin/io/github/sharon_xa/cinemakom/MainActivity.kt` (lines 84–90), `lib/data/repositories/download_paths.dart` (line 138)
  - **Problem:** `hasLegacyStoragePermission()` checks the permission without ever requesting it, so API 24–28 devices always silently fall back to the private app folder instead of asking first (§5.6).
  - **Fix:** Request `WRITE_EXTERNAL_STORAGE` before the first download on API 24–28 (falling back to the app folder if denied).

- [ ] **13. Fix UI, RTL, overflow, and missing-file display bugs (phone & TV)**
  - **Where:**
    - `lib/features/downloads/download_actions.dart`:
      - Wrap `showDownloadDetails` `AlertDialog.content` `Column` (lines 270–299) in `SingleChildScrollView` to prevent RenderFlex overflow on long engine errors / paths.
      - Use `context.joinMeta` for mixed-script strings on lines 159–160 (`title · S1 E2`) and lines 399–400 (`Downloading · 42%`).
      - Update `DownloadPill` (lines 387–401) and `EpisodeDownloadButton` (lines 429–442) to reflect `isDownloadMissingProvider` (*"File removed"* instead of *"Downloaded"*).
    - `lib/features/downloads/downloads_screen.dart`:
      - Wrap formatted sizes in `context.isolate(...)` for `downloadsStorageLine` (lines 87–90).
      - Exclude missing (`File removed`) rows from `finishedBytes` / `"Downloads use X"` (line 80).
    - `lib/tv/screens/downloads/tv_downloads_screen.dart` & `lib/tv/widgets/tv_downloads.dart`:
      - Exclude missing rows from TV's `used` calculation and include `tempBytes` (matching phone).
      - Reflect `isDownloadMissingProvider` in `TvMovieDownloadButton` and `TvEpisodeDownloadButton`.
      - Provide a way on `TvDownloadsScreen` itself to open **Details** for active/failed rows (currently OK goes to title page with no Details button on the Downloads row).

---

## Low / Cleanup

- [ ] **14. Minor hygiene**
  - Clear `_lastProgressSavedAt` on `_fail()` and `pause()` in `lib/data/repositories/downloads_repository.dart`.
  - Decide whether to keep `Download.contentUri` (schema 4) for future MediaStore fallback or document why it remains unused now that `Files.move` into `Movies/Cinemakom` succeeded on Android 15.

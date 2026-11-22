import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/downloads/background_file_downloader.dart';
import '../../core/downloads/connectivity_monitor.dart';
import '../../core/downloads/downloader.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_providers.dart';
import '../../core/platform/platform_info.dart';
import '../../core/platform/storage_space.dart';
import '../../core/storage/preferences.dart';
import '../../features/player/quality.dart';
import '../models/download.dart';
import '../models/media_item.dart';
import '../models/playback_models.dart';
import 'download_paths.dart';
import 'download_store.dart';
import 'downloads_janitor.dart';
import 'library_repository.dart';
import 'media_repository.dart';

export 'download_paths.dart'
    show DownloadRoot, defaultDesktopFolder, platformDownloadRoot;

/// What happened when the user asked to resume or retry a download
/// (docs/DOWNLOADS.md §5.5).
sealed class ResumeOutcome {
  const ResumeOutcome();
}

/// Resumed from the partial file, or started over in the same quality.
class ResumeStarted extends ResumeOutcome {
  const ResumeStarted({required this.startedOver});

  final bool startedOver;
}

/// The stored quality is gone from the server: ask the user before switching
/// to [fallback] (which starts over from 0).
class ResumeQualityGone extends ResumeOutcome {
  const ResumeQualityGone({
    required this.previousQuality,
    required this.fallback,
    required this.available,
  });

  final String previousQuality;
  final VideoSource fallback;
  final List<VideoSource> available;
}

/// Could not resume (no stream, network error, or row missing/complete).
class ResumeFailed extends ResumeOutcome {
  const ResumeFailed([this.problem]);

  final DownloadProblem? problem;
}

/// A stream a title can be downloaded in, with its size when known.
class DownloadChoice {
  const DownloadChoice(this.source, this.bytes);

  final VideoSource source;
  final int? bytes;
}

/// A downloaded file, ready to play offline.
class LocalPlayback {
  const LocalPlayback({
    required this.path,
    required this.quality,
    required this.subtitles,
  });

  final String path;
  final String quality;

  /// Absolute paths, with their language and format.
  final List<SubtitleTrack> subtitles;
}

/// Downloads (PLAN.md Phase 6, docs/DOWNLOADS.md): the video with its plain
/// Arabic and English subtitles (and the styled one where the player can draw
/// it), saved progress, state rules, pause, resume, delete, and offline
/// playback.
///
/// Signed stream URLs expire, so a download is always started, resumed or
/// retried with a fresh one (`MediaRepository.streams(fresh: true)`).
class DownloadsRepository {
  DownloadsRepository({
    required this._store,
    required this._downloader,
    required this._media,
    required this._api,
    required this._root,
    ConnectivityMonitor? connectivity,
    DownloadsJanitor? janitor,
    this.styledSubtitles = true,
    DateTime Function()? clock,
    Duration Function()? elapsed,
    this.progressSaveInterval = const Duration(seconds: 2),
    this.stallGuardDuration = const Duration(seconds: 8),
    this.rescheduleGrace = const Duration(seconds: 6),
    this.reconcileCooldown = const Duration(seconds: 5),
    this.serverRetryBaseDelay = const Duration(seconds: 2),
    this.userPauseGrace = const Duration(seconds: 3),
    this.internalCancelWindow = const Duration(seconds: 30),
    this.reconnectRetryBaseDelay = const Duration(seconds: 5),
    this.slowRetryDelays = const [
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 20),
      Duration(minutes: 30),
    ],
  }) : _clock = clock ?? DateTime.now,
       _elapsed = elapsed ?? _stopwatch(),
       _connectivity = connectivity ?? const AlwaysOnlineConnectivity(),
       _janitor = janitor ?? DownloadsJanitor(clock: clock);

  final DownloadStore _store;
  final Downloader _downloader;
  final MediaRepository _media;
  final ApiClient _api;
  final Future<DownloadRoot> Function() _root;
  final DateTime Function() _clock;

  /// A monotonic clock for the short in-memory windows ([userPauseGrace],
  /// [internalCancelWindow]); [_clock] dates the rows.
  final Duration Function() _elapsed;
  final ConnectivityMonitor _connectivity;
  final DownloadsJanitor _janitor;

  /// Minimum interval between persisting running progress to the database.
  final Duration progressSaveInterval;

  /// How long an engine `paused` the app didn't ask for waits for the next
  /// run before the engine is asked again (rule 4). Foreground mode leaves
  /// no time limits, so such a pause is nearly always the notification's
  /// Pause button: still paused then means paused by the user; unknown to
  /// the engine means [DownloadProblem.interrupted].
  final Duration stallGuardDuration;

  /// How long startup reconcile waits for `background_downloader`'s 5 s
  /// `rescheduleKilledTasks` before marking unknown active tasks interrupted.
  final Duration rescheduleGrace;

  /// Minimum time between automatic lifecycle/screen reconciles.
  final Duration reconcileCooldown;

  /// Initial backoff for automatic HTTP 5xx retries (2 s, 4 s, 8 s).
  final Duration serverRetryBaseDelay;

  /// After the app pauses a task, how long the engine's last progress and
  /// `running` events (sent while it stops) are ignored. Later ones mean
  /// the task runs again, e.g. resumed from the notification (rule 2).
  final Duration userPauseGrace;

  /// How long after the app cancels a task its `canceled` event is taken as
  /// the app's own. Any other `canceled` is the notification's Cancel.
  final Duration internalCancelWindow;

  /// First wait before asking again for a fresh URL when the network came
  /// back but the API isn't reachable yet (5 s, 10 s, 20 s, …).
  final Duration reconnectRetryBaseDelay;

  /// How often [reconnectRetryBaseDelay] backs off before the row is left
  /// "Waiting for connection" for the next network change or the user.
  static const reconnectRetries = 5;

  /// After a download fails for a reason that may pass (connection,
  /// interruption, server), how long until it continues by itself, then
  /// again, while the app runs. On a slow or flaky connection the engine's
  /// own 10 retries are spent in about 17 minutes; these keep a big file
  /// going from its partial file for hours more (docs/DOWNLOADS.md §5.5).
  final List<Duration> slowRetryDelays;

  /// The problems a download continues from by itself: on these delays,
  /// when the app comes to the front (Android also lets background work
  /// run again then), and when the network returns.
  static const passingProblems = {
    DownloadProblem.network,
    DownloadProblem.interrupted,
    DownloadProblem.server,
    DownloadProblem.linkExpired,
  };

  /// Two automatic continues of the same download are at least this apart.
  static const autoContinueGap = Duration(seconds: 60);

  /// Whether styled (ASS) subtitles are saved too: the player can draw them
  /// everywhere but on Android (PLAYER.md §2, decision 7).
  final bool styledSubtitles;

  /// Engine events, the user's actions and startup all read a row and
  /// write it back, so they run one at a time: a late progress event must
  /// never turn a finished download back into a running one.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  final _progress = <String, DownloadProgress>{};
  final _progressChanges = StreamController<void>.broadcast();
  final _missing = <String>{};
  final _missingChanges = StreamController<void>.broadcast();
  final _lastProgressSavedAt = <String, DateTime>{};
  DownloadNotices? _notices;

  /// Tasks currently being paused by the user or connectivity handler, so
  /// the engine's matching `paused` event is recognized as intentional.
  final _pendingUserPause = <String>{};
  final _pendingNetworkPause = <String>{};

  /// When the app last paused each task ([userPauseGrace]) and cancelled it
  /// ([internalCancelWindow]), on [_elapsed].
  final _userPausedAt = <String, Duration>{};
  final _internalCancelAt = <String, Duration>{};

  /// Fresh-URL attempts after the network came back, by task.
  final _reconnectAttempts = <String, int>{};

  /// Slow retries after a passing failure, by task, and when each download
  /// last continued by itself (on [_elapsed]).
  final _slowRetries = <String, int>{};
  final _autoContinuedAt = <String, Duration>{};

  /// What the connectivity monitor said last (online until it says not).
  bool _online = true;

  /// The Phase 6 download folder (app-private, Android), swept as private.
  String? _legacyRoot;

  /// Tasks already auto-retried once for expired link / timeout / restart.
  final _autoRetried = <String>{};
  final _timeoutRetried = <String>{};
  final _restartRetried = <String>{};
  final _serverRetries = <String, int>{};

  /// Active timers (cancelled in [dispose] so tests never leak timers).
  final _stallTimers = <String, Timer>{};
  final _retryTimers = <String, Timer>{};
  Timer? _rescheduleTimer;
  StreamSubscription<DownloaderEvent>? _eventsSub;
  StreamSubscription<bool>? _connectivitySub;

  bool _started = false;
  bool _disposed = false;
  DateTime? _startedAt;
  DateTime? _lastReconcileAt;

  void _log(String message) => debugPrint('[downloads] $message');

  void dispose() {
    _disposed = true;
    _eventsSub?.cancel();
    _connectivitySub?.cancel();
    _rescheduleTimer?.cancel();
    _rescheduleTimer = null;
    for (final t in _stallTimers.values) {
      t.cancel();
    }
    _stallTimers.clear();
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    _retryTimers.clear();
    _progressChanges.close();
    _missingChanges.close();
  }

  Stream<List<Download>> watchAll() => _store.watchAll();

  /// Task IDs tapped in system notifications (opens Downloads tab, §5.9).
  Stream<String> get notificationTaps => _downloader.notificationTaps;

  /// Video IDs of `complete` rows whose finished file was removed or moved
  /// outside the app (docs/DOWNLOADS.md §5.8).
  Stream<Set<String>> watchMissing() {
    StreamSubscription<void>? changes;
    late final StreamController<Set<String>> out;
    out = StreamController(
      onListen: () {
        out.add(Set.of(_missing));
        changes = _missingChanges.stream.listen(
          (_) => out.add(Set.of(_missing)),
        );
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  void _setMissing(Set<String> next) {
    if (_disposed) return;
    if (_missing.length == next.length && _missing.containsAll(next)) return;
    _missing
      ..clear()
      ..addAll(next);
    _missingChanges.add(null);
  }

  void _markMissing(String videoId) {
    if (_disposed) return;
    if (_missing.add(videoId)) _missingChanges.add(null);
  }

  void _clearMissing(String videoId) {
    if (_disposed) return;
    if (_missing.remove(videoId)) _missingChanges.add(null);
  }

  Future<Download?> get(String videoId) => _store.get(videoId);

  /// The absolute path where [d]'s video file lives (or will live).
  Future<String> filePath(Download d) => _downloader.pathOf(_spot(d));

  /// The running downloads' progress, by video ID.
  Stream<Map<String, DownloadProgress>> watchProgress() {
    StreamSubscription<void>? changes;
    late final StreamController<Map<String, DownloadProgress>> out;
    out = StreamController(
      onListen: () {
        out.add(Map.of(_progress));
        changes = _progressChanges.stream.listen(
          (_) => out.add(Map.of(_progress)),
        );
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  void _setProgress(String id, DownloadProgress? value) {
    if (_disposed) return;
    if (value == null) {
      if (_progress.remove(id) == null) return;
    } else {
      _progress[id] = value;
    }
    _progressChanges.add(null);
  }

  int _currentBytes(Download d) {
    final p = _progress[d.videoId];
    final total = p?.expectedBytes ?? d.totalBytes;
    if (p != null && total != null && total > 0) {
      return (total * p.fraction).round().clamp(0, total);
    }
    return d.downloadedBytes;
  }

  void _clearTimers(String id) {
    _stallTimers.remove(id)?.cancel();
    _retryTimers.remove(id)?.cancel();
  }

  void _clearRetryCounters(String id) {
    _autoRetried.remove(id);
    _timeoutRetried.remove(id);
    _restartRetried.remove(id);
    _serverRetries.remove(id);
    _reconnectAttempts.remove(id);
    _slowRetries.remove(id);
  }

  /// Forgets what this session knew about [id] once its row is gone or done.
  void _forget(String id) {
    _clearTimers(id);
    _clearRetryCounters(id);
    _lastProgressSavedAt.remove(id);
    _userPausedAt.remove(id);
  }

  bool _within(Map<String, Duration> at, String id, Duration window) {
    final t = at[id];
    return t != null && _elapsed() - t < window;
  }

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// The app paused [id] moments ago: the engine may still be stopping.
  bool _stopping(String id) => _within(_userPausedAt, id, userPauseGrace);

  /// Cancels [id] in the engine, remembering it was the app's own cancel so
  /// its `canceled` event doesn't delete the row (rule 1 still removes the
  /// engine's task, resume data and record).
  Future<void> _cancelTask(String id) async {
    _internalCancelAt[id] = _elapsed();
    await _downloader.cancel(id);
  }

  void _armStallGuard(String id) {
    if (_disposed) return;
    _stallTimers.remove(id)?.cancel();
    _stallTimers[id] = Timer(stallGuardDuration, () {
      _stallTimers.remove(id);
      if (!_disposed) unawaited(_serial(() => _onStallGuard(id)));
    });
  }

  /// A download this far along is finishing: the engine is moving the file
  /// into place and its last events are due.
  static const _endFraction = 0.99;

  Future<void> _onStallGuard(String id) async {
    final d = await _store.get(id);
    if (d == null || d.status != DownloadStatus.running) return;
    final ending = (_progress[id]?.fraction ?? 0) >= _endFraction;
    // Status updates the engine couldn't hand over (it keeps them natively):
    // they arrive as events, after this check.
    if (ending) await _downloader.sync();
    final info = (await _downloader.known())[id];
    final state = info?.state;
    final done = _currentBytes(d);
    switch (state) {
      case DownloaderState.running || DownloaderState.queued:
        _log('$id stall-guard check: engine still ${state!.name}');
        // Moving a big file can take a while: keep asking until it ends.
        if (ending) _armStallGuard(id);
      case DownloaderState.paused:
        // Nothing ran again: paused outside the app (the notification's
        // Pause). It keeps its resume data, so it's the user's pause.
        _setProgress(id, null);
        _log(
          '$id running -> paused (outside the app, engine paused) '
          'bytes=$done/${d.totalBytes ?? "?"}',
        );
        await _store.put(
          d.copyWith(
            status: DownloadStatus.paused,
            pausedByUser: true,
            downloadedBytes: done,
            updatedAt: _clock(),
          ),
        );
      case DownloaderState.complete:
        await _complete(d.copyWith(downloadedBytes: done));
      case DownloaderState.failed:
        _setProgress(id, null);
        await _failFromStatus(
          d.copyWith(downloadedBytes: done),
          info?.failure ?? DownloaderStatus(id, DownloaderState.failed),
        );
      case DownloaderState.canceled || null:
        _setProgress(id, null);
        _log(
          '$id running -> failed reason=interrupted (stall guard, '
          'engine=${state?.name ?? "none"}) bytes=$done/${d.totalBytes ?? "?"}',
        );
        await _fail(
          d.copyWith(downloadedBytes: done),
          DownloadProblem.interrupted,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Start & reconcile

  /// Starts the engine and catches up with what happened while the app was
  /// closed. Called once, at startup.
  Future<void> start(DownloadNotices notices) async {
    if (_started) return;
    _started = true;
    _startedAt = _clock();
    _eventsSub = _downloader.events.listen(
      (e) => unawaited(_serial(() => _onEvent(e))),
    );
    _notices = notices;
    try {
      final root = await _root();
      final partial = await platformPartialDir(root);
      await _downloader.start(partialDir: partial);
      await _downloader.setNotices(notices);
      // Migrate Phase 6 downloads from app-private Downloads into public
      // Movies/Cinemakom on Android (docs/DOWNLOADS.md §5.6): finished ones
      // move, unfinished ones start over in the new folder.
      final legacy = _legacyRoot = await legacyAndroidDownloadRoot();
      if (legacy != null && root.baseDirectory == 'root') {
        await _serial(() async {
          final result = await migrateLegacyDownloads(
            store: _store,
            legacyRoot: legacy,
            targetRoot: root.directory,
            pathOf: (d) => _downloader.pathOf(_spot(d)),
            onMoved: scanMediaFile,
            cancelTask: _cancelTask,
          );
          for (final id in result.restarted) {
            await _resume(id, forceRestart: true, automatic: true);
          }
        });
      }
      _lastReconcileAt = _clock();
      await _serial(() => _reconcile(initial: true));
    } on Object catch (e, stack) {
      // Startup never fails because of downloads; they show as failed.
      _log('failed to start: $e\n$stack');
    }
    // Only once the engine runs: the first answer (online) may resume
    // downloads that waited for a connection while the app was closed.
    if (!_disposed) {
      _connectivitySub = _connectivity.onChanged.listen(
        (online) => unawaited(_serial(() => _onConnectivity(online))),
      );
    }
  }

  /// Pauses running downloads when the network drops (keeping their resume
  /// data indefinitely, "Waiting for connection") and resumes them with
  /// fresh URLs when it returns (docs/DOWNLOADS.md §5.5).
  ///
  /// Queued downloads are left to the engine: one in the holding queue has
  /// nothing to lose, and one waiting to retry can't be paused, and
  /// cancelling it would throw its resume data away. The engine retries it
  /// (10 times, 2 s to 512 s apart).
  Future<void> _onConnectivity(bool online) async {
    if (_disposed) return;
    _online = online;
    final rows = await _store.all();
    if (!online) {
      for (final d in rows) {
        if (d.status != DownloadStatus.running) continue;
        final done = _currentBytes(d);
        _pendingNetworkPause.add(d.videoId);
        try {
          if (!await _downloader.pause(d.videoId)) {
            // Not running in the engine any more (finishing, failing or
            // between retries): its own events say what happened.
            _log('${d.videoId} offline: engine could not pause, left as is');
            continue;
          }
          _clearTimers(d.videoId);
          _setProgress(d.videoId, null);
          _log(
            '${d.videoId} running -> paused (waiting for connection) '
            'bytes=$done/${d.totalBytes ?? "?"}',
          );
          await _store.put(
            d.copyWith(
              status: DownloadStatus.paused,
              pausedByUser: false,
              downloadedBytes: done,
              updatedAt: _clock(),
            ),
          );
        } finally {
          _pendingNetworkPause.remove(d.videoId);
        }
      }
    } else {
      for (final d in rows) {
        if (!d.isWaitingForConnection) continue;
        _reconnectAttempts.remove(d.videoId);
        _log('${d.videoId} network back -> auto-resuming');
        await _resume(d.videoId, automatic: true);
      }
      await _continueFailed('network back');
    }
  }

  /// Continues every download that failed for a passing reason, from its
  /// partial file (rule 5), at most once a minute each. One that could only
  /// start over with bytes saved is left to the user's Retry, so a lot of
  /// downloaded data is never thrown away without them seeing it.
  Future<void> _continueFailed(String why) async {
    if (_disposed || !_online) return;
    for (final d in await _store.all()) {
      if (d.status != DownloadStatus.failed ||
          !passingProblems.contains(d.problem)) {
        continue;
      }
      if (_within(_autoContinuedAt, d.videoId, autoContinueGap)) continue;
      if (d.downloadedBytes > 0 && !await _downloader.canResume(d.videoId)) {
        continue;
      }
      _autoContinuedAt[d.videoId] = _elapsed();
      _log('${d.videoId} failed (${d.problem!.name}) -> continuing ($why)');
      await _resume(d.videoId, automatic: true);
    }
  }

  /// After a passing failure, continues [id] by itself later
  /// ([slowRetryDelays], the last one repeating up to 12 tries, about 5 h).
  void _scheduleSlowRetry(String id) {
    if (_disposed || slowRetryDelays.isEmpty) return;
    final attempt = (_slowRetries[id] ?? 0) + 1;
    if (attempt > 12) {
      _log('$id no more slow retries; Retry or a restart continues it');
      return;
    }
    _slowRetries[id] = attempt;
    final delay =
        slowRetryDelays[(attempt - 1).clamp(0, slowRetryDelays.length - 1)];
    _log('$id slow retry $attempt in ${delay.inMinutes} min');
    _retryTimers.remove(id)?.cancel();
    _retryTimers[id] = Timer(delay, () {
      _retryTimers.remove(id);
      if (_disposed) return;
      unawaited(
        _serial(() async {
          final d = await _store.get(id);
          if (d == null ||
              d.status != DownloadStatus.failed ||
              !passingProblems.contains(d.problem)) {
            return;
          }
          if (!_online) return; // The network's return continues it.
          if (d.downloadedBytes > 0 && !await _downloader.canResume(id)) {
            return;
          }
          _autoContinuedAt[id] = _elapsed();
          _log('$id failed (${d.problem!.name}) -> continuing (slow retry)');
          await _resume(id, automatic: true);
        }),
      );
    });
  }

  /// The network is back but a fresh URL couldn't be fetched (DNS not ready,
  /// API down): stays "Waiting for connection" and asks again with backoff,
  /// rather than failing (PR #4 review, high 5).
  void _retryReconnect(String id) {
    if (_disposed) return;
    final attempt = (_reconnectAttempts[id] ?? 0) + 1;
    if (attempt > reconnectRetries) {
      _log('$id still no fresh URL after $reconnectRetries tries: waiting');
      return;
    }
    _reconnectAttempts[id] = attempt;
    final delay = reconnectRetryBaseDelay * (1 << (attempt - 1));
    _log('$id fresh URL failed -> retry $attempt in ${delay.inSeconds}s');
    _retryTimers.remove(id)?.cancel();
    _retryTimers[id] = Timer(delay, () {
      _retryTimers.remove(id);
      if (_disposed) return;
      unawaited(
        _serial(() async {
          final d = await _store.get(id);
          if (d != null && d.isWaitingForConnection) {
            await _resume(id, automatic: true);
          }
        }),
      );
    });
  }

  /// Runs [DownloadsJanitor] to remove stray temp files, half-written videos,
  /// orphan subtitles and empty folders (docs/DOWNLOADS.md §5.7).
  ///
  /// [exclude]: rows whose engine task was just cancelled for a restart, so
  /// their old temp file doesn't keep a slot.
  Future<JanitorReport> _sweep({Set<String> exclude = const {}}) async {
    try {
      final rows = await _store.all();
      final tempDirs = await _downloader.tempDirs();
      final root = await _root();
      // The root as an absolute folder (the fallback names it by base
      // directory).
      final rootDir = root.baseDirectory == 'root'
          ? root.directory
          : p.dirname(
              await _downloader.pathOf(
                FileSpot(root.baseDirectory, root.directory, 'x'),
              ),
            );
      final legacy = _legacyRoot;
      final protectedTemp = await _downloader.protectedTempFiles({
        for (final d in rows)
          if (d.status.isActive) d.videoId,
      });
      return await _janitor.sweep(
        rows: rows,
        tempDirs: tempDirs,
        downloadRoots: {rootDir},
        privateRoots: [?legacy],
        pathOf: (d) => _downloader.pathOf(_spot(d)),
        canResume: _downloader.canResume,
        exclude: exclude,
        protectedTemp: protectedTemp,
      );
    } on Object catch (e) {
      _log('janitor error: $e');
      return const JanitorReport();
    }
  }

  /// Bytes currently occupied by engine temp files (for the storage line).
  Future<int> tempBytes() async {
    try {
      return await _janitor.tempBytes(await _downloader.tempDirs());
    } on Object {
      return 0;
    }
  }

  /// Re-checks every row against the engine (docs/DOWNLOADS.md §5.4). Called
  /// on `AppLifecycleState.resumed` and when Downloads opens; throttled to at
  /// most once every [reconcileCooldown] unless [force] is true.
  Future<void> reconcile({bool force = false}) async {
    if (!_started || _disposed) return;
    final now = _clock();
    if (!force &&
        _lastReconcileAt != null &&
        now.difference(_lastReconcileAt!) < reconcileCooldown) {
      return;
    }
    _lastReconcileAt = now;
    try {
      await _downloader.sync();
      await _serial(_reconcile);
    } on Object catch (e) {
      _log('reconcile error: $e');
    }
  }

  Future<void> setNotices(DownloadNotices notices) {
    _notices = notices;
    return _downloader.setNotices(notices);
  }

  Future<void> _reconcile({bool initial = false}) async {
    final known = await _downloader.known();
    final now = _clock();
    final inGrace =
        _startedAt != null &&
        rescheduleGrace > Duration.zero &&
        now.difference(_startedAt!) < rescheduleGrace;
    var hasPendingUnknown = false;
    final missingNow = <String>{};

    for (final d in await _store.all()) {
      if (!d.status.isActive) {
        final path = await _downloader.pathOf(_spot(d));
        if (!File(path).existsSync()) {
          missingNow.add(d.videoId);
        } else if (d.subtitles.isNotEmpty) {
          // Re-fetch any subtitle removed outside the app in the background (§5.8).
          final dir = p.dirname(path);
          final subMissing = d.subtitles.any(
            (s) => !File(p.join(dir, s.fileName)).existsSync(),
          );
          if (subMissing) {
            unawaited(_restoreMissingSubtitles(d, path));
          }
        }
        continue;
      }
      final info = known[d.videoId];
      final state = info?.state;

      // Pick up any higher byte count reported by the engine record.
      var row = d;
      if (info != null) {
        final total = info.expectedBytes ?? d.totalBytes;
        final done = (info.fraction != null && total != null && total > 0)
            ? (total * info.fraction!).round().clamp(0, total)
            : d.downloadedBytes;
        if (done > d.downloadedBytes ||
            (d.totalBytes == null && total != null)) {
          row = d.copyWith(downloadedBytes: done, totalBytes: total);
        }
      }

      if (state == DownloaderState.complete) {
        await _complete(row);
        continue;
      }

      // Safety net if a task finished while backgrounded and its status event
      // wasn't delivered before reconcile: the destination file only appears
      // once the download completes. Only a file of exactly the expected size
      // counts: one of unknown size may be a half-written copy (§3.4).
      if (state != DownloaderState.running && row.totalBytes != null) {
        try {
          final videoFile = File(await _downloader.pathOf(_spot(row)));
          if (videoFile.existsSync() &&
              videoFile.lengthSync() == row.totalBytes) {
            await _complete(row);
            continue;
          }
        } on FileSystemException {
          // Gone while checking: not finished.
        }
      }

      // The engine's own state wins, except moments after the app paused it
      // (rule 2): a task resumed from the notification, or rescheduled after
      // a reconcile marked it interrupted, is downloading again.
      final engineActive =
          state == DownloaderState.running || state == DownloaderState.queued;
      if (engineActive &&
          (row.status == DownloadStatus.failed ||
              row.status == DownloadStatus.paused) &&
          !_stopping(row.videoId)) {
        final next = state == DownloaderState.running
            ? DownloadStatus.running
            : DownloadStatus.queued;
        _clearTimers(row.videoId);
        _log('${row.videoId} reconcile ${row.status.name} -> ${next.name}');
        await _store.put(
          row.copyWith(
            status: next,
            pausedByUser: false,
            clearProblem: true,
            updatedAt: now,
          ),
        );
        continue;
      }
      if (row.status == DownloadStatus.failed) continue;

      if (state == null || state == DownloaderState.canceled) {
        // User-paused holding-queue tasks and connectivity-paused tasks are
        // allowed to have no active engine task.
        if (row.status == DownloadStatus.paused) continue;
        if (inGrace) {
          hasPendingUnknown = true;
          continue;
        }
        final resumable = await _downloader.canResume(row.videoId);
        _setProgress(row.videoId, null);
        _clearTimers(row.videoId);
        _log(
          '${row.videoId} reconcile ${row.status.name} -> failed '
          'reason=interrupted (unknown to engine, resumable=$resumable) '
          'bytes=${row.downloadedBytes}/${row.totalBytes ?? "?"}',
        );
        await _store.put(
          row.copyWith(
            status: DownloadStatus.failed,
            problem: DownloadProblem.interrupted,
            startedOver: !resumable && row.downloadedBytes > 0,
            updatedAt: now,
          ),
        );
      } else if (state == DownloaderState.failed) {
        _setProgress(row.videoId, null);
        _clearTimers(row.videoId);
        final failure =
            info?.failure ??
            DownloaderStatus(row.videoId, DownloaderState.failed);
        await _failFromStatus(row, failure);
      } else if (state == DownloaderState.paused) {
        if (row.status == DownloadStatus.paused) {
          if (row != d) await _store.put(row.copyWith(updatedAt: now));
        } else {
          // Paused in the engine, not by the app (rule 4): the notification's
          // Pause once nothing ran again for a while, else keep running and
          // let the guard check again.
          final stale =
              row.updatedAt != null &&
              now.difference(row.updatedAt!) >= stallGuardDuration;
          if (stale) {
            _setProgress(row.videoId, null);
            _clearTimers(row.videoId);
            _log(
              '${row.videoId} reconcile ${row.status.name} -> paused '
              '(outside the app) '
              'bytes=${row.downloadedBytes}/${row.totalBytes ?? "?"}',
            );
            await _store.put(
              row.copyWith(
                status: DownloadStatus.paused,
                pausedByUser: true,
                updatedAt: now,
              ),
            );
          } else {
            if (row != d) await _store.put(row.copyWith(updatedAt: now));
            _armStallGuard(row.videoId);
          }
        }
      } else if (state == DownloaderState.running) {
        // (A paused row the app is still stopping stays paused.)
        if (row.status == DownloadStatus.queued) {
          _clearTimers(row.videoId);
          _log('${row.videoId} reconcile ${row.status.name} -> running');
          await _store.put(
            row.copyWith(
              status: DownloadStatus.running,
              pausedByUser: false,
              clearProblem: true,
              updatedAt: now,
            ),
          );
        }
      }
    }

    _setMissing(missingNow);

    if (hasPendingUnknown && _rescheduleTimer == null && !_disposed) {
      final remaining = _startedAt == null
          ? rescheduleGrace
          : rescheduleGrace - now.difference(_startedAt!);
      final delay = remaining.isNegative ? Duration.zero : remaining;
      _rescheduleTimer = Timer(delay, () {
        _rescheduleTimer = null;
        if (!_disposed) unawaited(_serial(_reconcile));
      });
    } else if (!hasPendingUnknown) {
      await _sweep();
      await _continueFailed(initial ? 'app started' : 're-check');
    }
  }

  Future<void> _restoreMissingSubtitles(Download d, String videoPath) async {
    final dir = p.dirname(videoPath);
    final stem = p.basenameWithoutExtension(d.fileName);
    try {
      final tracks = oneTrackPerLanguage(await _media.subtitles(d.videoId));
      for (final s in d.subtitles) {
        final target = p.join(dir, s.fileName);
        if (File(target).existsSync()) continue;
        final track = tracks
            .where(
              (t) => t.languageCode == s.language && t.format.name == s.format,
            )
            .firstOrNull;
        if (track == null) continue;
        try {
          await _api.downloadFile(track.url, target);
          _log('${d.videoId} restored missing subtitle $stem (${s.language})');
        } on Object {
          // Offline or unavailable; try again next reconcile.
        }
      }
    } on Object {
      // Offline; skip silently.
    }
  }

  // ---------------------------------------------------------------------------
  // Choosing what to download

  /// Every quality of [videoId], highest first, with file sizes (asked of
  /// the CDN in parallel; `null` when it doesn't say).
  Future<List<DownloadChoice>> choices(String videoId) async {
    final sources = [...await _media.streams(videoId, fresh: true)]
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    final sizes = await Future.wait(
      sources.map((s) => _api.contentLength(s.url)),
    );
    return [
      for (var i = 0; i < sources.length; i++)
        DownloadChoice(sources[i], sizes[i]),
    ];
  }

  // ---------------------------------------------------------------------------
  // Downloading

  /// Downloads [item] (a movie), or its [episode], in [source]'s quality.
  /// Does nothing when it's already downloaded or on its way.
  Future<void> download(
    MediaItem item, {
    Episode? episode,
    required VideoSource source,
    int? bytes,
  }) async {
    // Android 7–9 asks for shared storage first (§5.6), outside the queue:
    // the dialog waits for the user, and engine events must not.
    await _downloader.askForStorage();
    await _serial(
      () => _download(item, episode: episode, source: source, bytes: bytes),
    );
  }

  Future<void> _download(
    MediaItem item, {
    Episode? episode,
    required VideoSource source,
    int? bytes,
  }) async {
    final videoId = episode?.id ?? item.id;
    final existing = await _store.get(videoId);
    if (existing != null && existing.status != DownloadStatus.failed) return;

    // Rule 1: a new attempt removes any old task, resume data and temp file.
    _forget(videoId);
    if (existing != null) {
      await _cancelTask(videoId);
      await _sweep(exclude: {videoId});
    }

    final root = await _root();
    final folder = p.join(
      root.directory,
      titleFolderName(item, fallback: item.seriesId),
    );
    final baseStem = videoFileStem(
      item,
      episode: episode,
      quality: source.label,
      fallback: videoId,
    );
    final stem = root.baseDirectory == 'root'
        ? uniqueFileStem(folder, baseStem, ext: '.mp4')
        : baseStem;
    final spot = FileSpot(root.baseDirectory, folder, '$stem.mp4');
    _clearMissing(videoId);

    final subtitles = await _saveSubtitles(videoId, spot, stem);
    final now = _clock();
    final download = Download(
      videoId: videoId,
      titleId: item.seriesId,
      title: item.title,
      season: episode?.season,
      episode: episode?.episode,
      episodeLast: episode == null || episode.numbering.last == episode.episode
          ? null
          : episode.numbering.last,
      finale: episode?.numbering.isFinale ?? false,
      posterUrl: item.posterUrl ?? item.hdPosterUrl,
      kind: item.kind,
      year: item.year,
      duration: episode?.duration ?? item.duration,
      quality: source.label,
      baseDirectory: spot.baseDirectory,
      directory: spot.directory,
      fileName: spot.fileName,
      subtitles: subtitles,
      totalBytes: bytes,
      downloadedBytes: 0,
      status: DownloadStatus.queued,
      pausedByUser: false,
      startedOver: false,
      addedAt: now,
      updatedAt: now,
    );
    await _store.put(download);
    await _downloader.askToNotify();
    _log(
      '$videoId none -> queued quality=${source.label} bytes=0/${bytes ?? "?"}',
    );
    if (!await _downloader.enqueue(_job(download, source.url))) {
      await _fail(download, DownloadProblem.unknown);
    }
  }

  /// Queues every episode in [episodes] that isn't downloaded yet, each in
  /// the quality closest to [height], with its own size (for the progress
  /// and the notification). Returns how many were queued.
  Future<int> downloadEpisodes(
    MediaItem series,
    List<Episode> episodes,
    int height,
  ) async {
    var queued = 0;
    for (final e in episodes) {
      final existing = await _store.get(e.id);
      if (existing != null && existing.status != DownloadStatus.failed) {
        continue;
      }
      final List<VideoSource> sources;
      try {
        sources = await _media.streams(e.id, fresh: true);
      } on Object {
        continue;
      }
      final source = pickQuality(sources, height);
      if (source == null) continue;
      await download(
        series,
        episode: e,
        source: source,
        bytes: await sizeOf(source),
      );
      queued++;
    }
    return queued;
  }

  /// [source]'s file size from the CDN, or `null` when it doesn't say.
  Future<int?> sizeOf(VideoSource source) async {
    try {
      return await _api.contentLength(source.url);
    } on Object {
      return null;
    }
  }

  /// The CDN serves ranges (206, strong ETag) but sends no `Accept-Ranges`
  /// on a plain 200, so background_downloader would think a download can't
  /// be paused or resumed. Asking for the whole file as a range from the
  /// first byte gets a 206, and resume adds its offset to this range's
  /// start (docs/API.md §3, File sizes and ranges).
  static const _wholeFile = {'Range': 'bytes=0-'};

  DownloadJob _job(Download d, String url) {
    final name = _displayName(d);
    return DownloadJob(
      taskId: d.videoId,
      url: url,
      headers: {...ApiClient.defaultHeaders, ..._wholeFile},
      spot: FileSpot(d.baseDirectory, d.directory, d.fileName),
      displayName: name,
      quality: d.quality,
      notice: _taskNotice(d, name),
    );
  }

  /// The notification texts of [d] (§5.9). The failed text stays generic:
  /// background_downloader fixes it when the task is queued and has no
  /// placeholder for the reason; the app shows the reason.
  DownloadTaskNotice? _taskNotice(Download d, String displayName) {
    final n = _notices;
    if (n == null) return null;
    final size = d.totalBytes != null && n.formatSize != null
        ? n.formatSize!(d.totalBytes!)
        : null;
    final runningParts = [
      d.quality,
      ?size,
      '{progress}',
      '{networkSpeed}',
      '{timeRemaining}',
    ];
    final completeBody = size != null
        ? (isAndroid && n.downloadedFolder != null
              ? n.downloadedFolder!(size)
              : n.downloadedSize != null
              ? n.downloadedSize!(size)
              : n.complete)
        : n.complete;
    return DownloadTaskNotice(
      runningTitle: displayName,
      runningBody: runningParts.join(' · '),
      pausedTitle: displayName,
      pausedBody: '${n.paused} · {progress}',
      completeTitle: displayName,
      completeBody: completeBody,
      errorTitle: displayName,
      errorBody: n.failed,
    );
  }

  static String _displayName(Download d) {
    final title = d.title.en ?? d.title.ar ?? '';
    return d.isEpisode
        ? '$title · S${_two(d.season!)}E${_two(d.episode!)}'
        : title;
  }

  /// Saves the plain Arabic and English subtitles (and the styled Arabic
  /// one when [styledSubtitles]) beside the video. Failures are skipped:
  /// a download never waits on its subtitles.
  Future<List<DownloadedSubtitle>> _saveSubtitles(
    String videoId,
    FileSpot spot,
    String stem,
  ) async {
    final List<SubtitleTrack> tracks;
    try {
      tracks = oneTrackPerLanguage(await _media.subtitles(videoId));
    } on Object {
      return const [];
    }
    final wanted = [
      for (final t in tracks)
        if ((t.languageCode == 'ar' || t.languageCode == 'en') &&
            (!t.isStyled || styledSubtitles))
          t,
    ];
    if (wanted.isEmpty) return const [];
    final String dir;
    try {
      dir = p.dirname(await _downloader.pathOf(spot));
      await Directory(dir).create(recursive: true);
    } on Object {
      return const [];
    }
    final saved = <DownloadedSubtitle>[];
    for (final t in wanted) {
      final name =
          '$stem.${t.languageCode}${t.isStyled ? '.styled' : ''}'
          '.${t.format.name}';
      try {
        await _api.downloadFile(t.url, p.join(dir, name));
        saved.add(
          DownloadedSubtitle(
            language: t.languageCode,
            fileName: name,
            format: t.format.name,
          ),
        );
      } on Object {
        // Without this one.
      }
    }
    return saved;
  }

  // ---------------------------------------------------------------------------
  // Controls

  Future<void> pause(String videoId) => _serial(() async {
    final d = await _store.get(videoId);
    if (d == null ||
        (d.status != DownloadStatus.running &&
            d.status != DownloadStatus.queued)) {
      return;
    }
    _clearTimers(videoId);
    final done = _currentBytes(d);
    _pendingUserPause.add(videoId);
    try {
      final paused = await _downloader.pause(videoId);
      if (!paused) {
        // Not running in the engine: in the holding queue (nothing saved
        // yet), or between retries, which the engine can't pause. Cancel it
        // and mark it paused; Resume enqueues it (docs/DOWNLOADS.md §5.2).
        // One between retries loses its resume data that way, and Resume
        // says "Started over".
        await _cancelTask(videoId);
      }
      _userPausedAt[videoId] = _elapsed();
      _lastProgressSavedAt.remove(videoId);
      _log(
        '$videoId ${d.status.name} -> paused (user${paused ? '' : ', engine cancel'}) '
        'bytes=$done/${d.totalBytes ?? "?"}',
      );
      await _store.put(
        d.copyWith(
          status: DownloadStatus.paused,
          pausedByUser: true,
          downloadedBytes: done,
          updatedAt: _clock(),
        ),
      );
      _setProgress(videoId, null);
    } finally {
      _pendingUserPause.remove(videoId);
    }
  });

  /// Resumes a paused download, or tries a failed one again, with a fresh
  /// URL: from the partial file when there is one, else from the start.
  ///
  /// When the stored quality is no longer available and [switchTo] is `null`,
  /// returns [ResumeQualityGone] without altering the download so the UI can
  /// ask the user first (docs/DOWNLOADS.md §5.5). Pass [switchTo] once the
  /// user confirms switching quality.
  Future<ResumeOutcome> resume(String videoId, {VideoSource? switchTo}) =>
      _serial(() {
        _clearRetryCounters(videoId);
        return _resume(videoId, switchTo: switchTo);
      });

  Future<ResumeOutcome> _resume(
    String videoId, {
    bool forceRestart = false,
    bool automatic = false,
    VideoSource? switchTo,
  }) async {
    final d = await _store.get(videoId);
    if (d == null || d.status == DownloadStatus.complete) {
      return const ResumeFailed();
    }
    _clearTimers(videoId);

    if (switchTo != null) {
      // The user confirmed another quality: start over in it (rule 1).
      return _restartIn(d, switchTo);
    }

    final String url;
    try {
      final sources = await _media.streams(videoId, fresh: true);
      final exact = sources.where((s) => s.label == d.quality).firstOrNull;
      if (exact == null) {
        final fallback = pickQuality(sources, _height(d.quality));
        if (fallback == null || automatic) {
          // Never switch quality silently on an automatic retry.
          await _fail(d, DownloadProblem.unavailable);
          return const ResumeFailed(DownloadProblem.unavailable);
        }
        _log(
          '$videoId quality ${d.quality} gone -> asking user (fallback=${fallback.label})',
        );
        return ResumeQualityGone(
          previousQuality: d.quality,
          fallback: fallback,
          available: sources,
        );
      }
      url = exact.url;
    } on Object {
      if (automatic && d.isWaitingForConnection) {
        // The network is back but the API isn't reachable yet.
        _retryReconnect(videoId);
        return const ResumeFailed(DownloadProblem.network);
      }
      await _fail(d, DownloadProblem.network);
      return const ResumeFailed(DownloadProblem.network);
    }
    _reconnectAttempts.remove(videoId);

    final queued = d.copyWith(
      status: DownloadStatus.queued,
      pausedByUser: false,
      clearProblem: true,
      updatedAt: _clock(),
    );
    await _store.put(queued);
    _userPausedAt.remove(videoId);

    if (!forceRestart &&
        await _downloader.resume(
          videoId,
          url,
          notice: _taskNotice(queued, _displayName(queued)),
        )) {
      _log(
        '$videoId ${d.status.name} -> queued (resume) '
        'bytes=${queued.downloadedBytes}/${queued.totalBytes ?? "?"}',
      );
      return const ResumeStarted(startedOver: false);
    }

    // Rule 1: no resume data (or forced restart) -> remove the old task and
    // its temp file first, then enqueue from 0.
    await _cancelTask(videoId);
    final hadProgress = d.downloadedBytes > 0;
    final restarted = queued.copyWith(
      downloadedBytes: 0,
      startedOver: hadProgress || forceRestart,
      updatedAt: _clock(),
    );
    await _store.put(restarted);
    await _sweep(exclude: {videoId});
    _log(
      '$videoId ${d.status.name} -> queued (restart, startedOver=${restarted.startedOver})',
    );
    if (!await _downloader.enqueue(_job(restarted, url))) {
      await _fail(restarted, DownloadProblem.unknown);
      return const ResumeFailed(DownloadProblem.unknown);
    }
    return ResumeStarted(startedOver: restarted.startedOver);
  }

  /// Starts [d] over from 0 in [source]'s quality: a new file name for the
  /// quality (its subtitles renamed to match, so players still pair them),
  /// the new size, and the old task and temp file gone (rule 1).
  Future<ResumeOutcome> _restartIn(
    Download d,
    VideoSource source, {
    bool startedOver = true,
  }) async {
    final videoId = d.videoId;
    await _cancelTask(videoId);
    final bytes = await sizeOf(source);
    var moved = d;
    if (source.label != d.quality) {
      final oldStem = p.basenameWithoutExtension(d.fileName);
      final ext = p.extension(d.fileName);
      // "Title 1080p (2)" -> "Title 720p", then made unique again.
      final bare = oldStem.replaceFirst(RegExp(r' \(\d+\)$'), '');
      final at = bare.lastIndexOf(d.quality);
      final newBase = at < 0
          ? '$bare ${source.label}'
          : bare.replaceRange(at, at + d.quality.length, source.label);
      final dir = p.dirname(await _downloader.pathOf(_spot(d)));
      final stem = d.baseDirectory == 'root'
          ? uniqueFileStem(dir, newBase, ext: ext)
          : newBase;
      final subtitles = <DownloadedSubtitle>[];
      for (final s in d.subtitles) {
        final name = s.fileName.startsWith(oldStem)
            ? '$stem${s.fileName.substring(oldStem.length)}'
            : s.fileName;
        try {
          if (name != s.fileName) {
            await File(p.join(dir, s.fileName)).rename(p.join(dir, name));
          }
          subtitles.add(
            DownloadedSubtitle(
              language: s.language,
              fileName: name,
              format: s.format,
            ),
          );
        } on FileSystemException {
          // Gone: without this one.
        }
      }
      moved = d.copyWith(
        quality: source.label,
        fileName: '$stem$ext',
        subtitles: subtitles,
      );
    }
    final next = moved.copyWith(
      status: DownloadStatus.queued,
      downloadedBytes: 0,
      totalBytes: bytes,
      clearTotalBytes: bytes == null,
      pausedByUser: false,
      startedOver: startedOver && d.downloadedBytes > 0,
      clearProblem: true,
      updatedAt: _clock(),
    );
    await _store.put(next);
    _userPausedAt.remove(videoId);
    await _sweep(exclude: {videoId});
    _log(
      '$videoId quality ${d.quality} -> ${source.label} (restart) '
      'bytes=0/${bytes ?? "?"}',
    );
    if (!await _downloader.enqueue(_job(next, source.url))) {
      await _fail(next, DownloadProblem.unknown);
      return const ResumeFailed(DownloadProblem.unknown);
    }
    return ResumeStarted(startedOver: next.startedOver);
  }

  /// Downloads again a finished download whose file was removed outside the
  /// app, in the same quality and place, with its subtitles saved again
  /// (docs/DOWNLOADS.md §5.8). The row stays as it is until the download
  /// can start: when its quality is gone it returns [ResumeQualityGone] so
  /// the UI can ask, then pass the user's pick as [switchTo].
  Future<ResumeOutcome> redownload(String videoId, {VideoSource? switchTo}) =>
      _serial(() async {
        final d = await _store.get(videoId);
        if (d == null) return const ResumeFailed();
        if (d.status != DownloadStatus.complete) {
          _clearRetryCounters(videoId);
          return _resume(videoId, switchTo: switchTo);
        }
        final VideoSource source;
        if (switchTo != null) {
          source = switchTo;
        } else {
          final List<VideoSource> sources;
          try {
            sources = await _media.streams(videoId, fresh: true);
          } on Object {
            return const ResumeFailed(DownloadProblem.network);
          }
          final exact = sources.where((s) => s.label == d.quality).firstOrNull;
          if (exact == null) {
            final fallback = pickQuality(sources, _height(d.quality));
            if (fallback == null) {
              return const ResumeFailed(DownloadProblem.unavailable);
            }
            return ResumeQualityGone(
              previousQuality: d.quality,
              fallback: fallback,
              available: sources,
            );
          }
          source = exact;
        }
        _forget(videoId);
        _clearMissing(videoId);
        // Subtitles removed with the video come back now, not after it.
        final path = await _downloader.pathOf(_spot(d));
        final stem = p.basenameWithoutExtension(d.fileName);
        final dir = p.dirname(path);
        final lost = d.subtitles.any(
          (s) => !File(p.join(dir, s.fileName)).existsSync(),
        );
        var row = d;
        if (lost || d.subtitles.isEmpty) {
          final saved = await _saveSubtitles(videoId, _spot(d), stem);
          if (saved.isNotEmpty) row = d.copyWith(subtitles: saved);
        }
        _log('$videoId complete (file removed) -> downloading again');
        return _restartIn(row, source, startedOver: false);
      });

  /// Stops a download that isn't finished and removes it.
  Future<void> cancel(String videoId) => delete(videoId);

  /// Removes a download, finished or not: its video, its partial file, its
  /// subtitles and its row.
  Future<void> delete(String videoId) => _serial(() => _delete(videoId));

  Future<void> _delete(String videoId) async {
    final d = await _store.get(videoId);
    if (d == null) return;
    _forget(videoId);
    _clearMissing(videoId);
    if (d.status.isActive) await _cancelTask(videoId);
    _setProgress(videoId, null);
    await _store.remove(videoId);
    _log('${d.videoId} ${d.status.name} -> deleted');
    final video = await _downloader.pathOf(_spot(d));
    final dir = p.dirname(video);
    for (final path in [
      video,
      for (final s in d.subtitles) p.join(dir, s.fileName),
    ]) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    try {
      final folder = Directory(dir);
      if (await folder.list().isEmpty) await folder.delete();
    } on FileSystemException {
      // Not empty, or gone.
    }
    await _sweep();
  }

  /// Removes every downloaded episode of [titleId] (or the movie).
  Future<void> deleteTitle(String titleId) => _serial(() async {
    for (final d in await _store.all()) {
      if (d.titleId == titleId) await _delete(d.videoId);
    }
  });

  // ---------------------------------------------------------------------------
  // Playing

  /// [videoId]'s downloaded file and subtitles, when it's complete and the
  /// file is still there.
  Future<LocalPlayback?> playable(String videoId) async {
    final d = await _store.get(videoId);
    if (d == null || d.status != DownloadStatus.complete) return null;
    final path = await _downloader.pathOf(_spot(d));
    if (!await File(path).exists()) {
      _markMissing(videoId);
      return null;
    }
    _clearMissing(videoId);
    final dir = p.dirname(path);
    return LocalPlayback(
      path: path,
      quality: d.quality,
      subtitles: [
        for (final s in d.subtitles)
          if (File(p.join(dir, s.fileName)).existsSync())
            SubtitleTrack(
              url: Uri.file(p.join(dir, s.fileName)).toString(),
              languageCode: s.language,
              format:
                  SubtitleFormat.values.asNameMap()[s.format] ??
                  SubtitleFormat.srt,
            ),
      ],
    );
  }

  /// The downloaded episodes of [titleId], in order, for playing offline.
  Future<List<Episode>> downloadedEpisodes(String titleId) async {
    final episodes =
        [
          for (final d in await _store.all())
            if (d.titleId == titleId && d.status == DownloadStatus.complete)
              ?d.asEpisode,
        ]..sort(
          (a, b) => a.season != b.season
              ? a.season.compareTo(b.season)
              : a.episode.compareTo(b.episode),
        );
    return episodes;
  }

  /// The bytes the finished downloads take (plus saved partial bytes).
  Future<int> usedBytes() async {
    var total = 0;
    for (final d in await _store.all()) {
      if (d.status == DownloadStatus.complete) {
        if (_missing.contains(d.videoId)) continue;
        total += d.totalBytes ?? 0;
      } else {
        total += _currentBytes(d);
      }
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Engine events

  /// Whether the engine runs [d] again although the row says it stopped:
  /// resumed from the notification, or rescheduled (rule 2). Not moments
  /// after the app paused it, when its last events still arrive, and, for a
  /// progress event, only when it's past the saved bytes (a late one from
  /// before the stop never is).
  bool _runsAgain(Download d, {int? done}) {
    if (d.status != DownloadStatus.paused &&
        d.status != DownloadStatus.failed) {
      return false;
    }
    if (_stopping(d.videoId)) return false;
    // Waiting for connection: any sign of life counts.
    if (d.isWaitingForConnection) return true;
    return done == null || done > d.downloadedBytes;
  }

  Future<void> _onEvent(DownloaderEvent event) async {
    final d = await _store.get(event.taskId);
    if (d == null) return;
    switch (event) {
      case DownloaderProgress():
        final total = event.expectedBytes ?? d.totalBytes;
        final done = total != null && total > 0
            ? (total * event.fraction).round().clamp(0, total)
            : d.downloadedBytes;
        // Rule 2 & §5.2: progress arriving means running, except when
        // complete, or stopped and not running again.
        if (d.status == DownloadStatus.complete) return;
        final stopped =
            d.status == DownloadStatus.failed ||
            d.status == DownloadStatus.paused;
        if (stopped && !_runsAgain(d, done: done)) return;
        _stallTimers.remove(d.videoId)?.cancel();
        // The last percent: if the engine goes quiet now, its `complete` may
        // be stuck on the native side (seen on the TCL: 99% until the
        // Downloads tab's reconcile fetched it). The guard asks for it.
        if (event.fraction >= _endFraction) _armStallGuard(d.videoId);
        _setProgress(
          d.videoId,
          DownloadProgress(
            fraction: event.fraction,
            expectedBytes: total,
            bytesPerSecond: event.bytesPerSecond,
            timeLeft: event.timeLeft,
          ),
        );
        final now = _clock();
        final lastSave = _lastProgressSavedAt[d.videoId];
        final shouldPersist =
            d.status != DownloadStatus.running ||
            d.startedOver ||
            (d.totalBytes == null && event.expectedBytes != null) ||
            (done != d.downloadedBytes &&
                (lastSave == null ||
                    now.difference(lastSave) >= progressSaveInterval));
        if (shouldPersist) {
          _lastProgressSavedAt[d.videoId] = now;
          // Data flows again: the next failure starts the slow retries over.
          _slowRetries.remove(d.videoId);
          if (d.status != DownloadStatus.running) {
            _log(
              '${d.videoId} ${d.status.name} -> running (progress'
              '${stopped ? ', resumed outside the app' : ''}) '
              'bytes=$done/${total ?? "?"}',
            );
          }
          await _store.put(
            d.copyWith(
              status: DownloadStatus.running,
              totalBytes: total,
              downloadedBytes: done,
              pausedByUser: false,
              startedOver: false,
              clearProblem: true,
              updatedAt: now,
            ),
          );
        }
      case DownloaderStatus(:final state):
        switch (state) {
          case DownloaderState.queued:
            if (d.status == DownloadStatus.queued ||
                d.status == DownloadStatus.running ||
                _runsAgain(d)) {
              final done = _currentBytes(d);
              if (d.status != DownloadStatus.queued ||
                  done != d.downloadedBytes) {
                _log(
                  '${d.videoId} ${d.status.name} -> queued '
                  'bytes=$done/${d.totalBytes ?? "?"}',
                );
                await _store.put(
                  d.copyWith(
                    status: DownloadStatus.queued,
                    downloadedBytes: done,
                    pausedByUser: false,
                    clearProblem: true,
                    updatedAt: _clock(),
                  ),
                );
              }
            }
          case DownloaderState.running:
            if (d.status == DownloadStatus.queued ||
                d.status == DownloadStatus.running ||
                _runsAgain(d)) {
              _stallTimers.remove(d.videoId)?.cancel();
              if (d.status != DownloadStatus.running) {
                _log(
                  '${d.videoId} ${d.status.name} -> running '
                  'bytes=${d.downloadedBytes}/${d.totalBytes ?? "?"}',
                );
                await _store.put(
                  d.copyWith(
                    status: DownloadStatus.running,
                    pausedByUser: false,
                    clearProblem: true,
                    updatedAt: _clock(),
                  ),
                );
              }
            }
          case DownloaderState.paused:
            if (d.status == DownloadStatus.complete ||
                d.status == DownloadStatus.failed) {
              return;
            }
            final done = _currentBytes(d);
            if (_pendingUserPause.contains(d.videoId) ||
                (d.status == DownloadStatus.paused && d.pausedByUser)) {
              _clearTimers(d.videoId);
              _setProgress(d.videoId, null);
              await _store.put(
                d.copyWith(
                  status: DownloadStatus.paused,
                  pausedByUser: true,
                  downloadedBytes: done,
                  updatedAt: _clock(),
                ),
              );
            } else if (_pendingNetworkPause.contains(d.videoId) ||
                d.isWaitingForConnection) {
              _clearTimers(d.videoId);
              _setProgress(d.videoId, null);
              await _store.put(
                d.copyWith(
                  status: DownloadStatus.paused,
                  pausedByUser: false,
                  downloadedBytes: done,
                  updatedAt: _clock(),
                ),
              );
            } else {
              // Rule 4 (§5.2): a `paused` the app didn't ask for. Either the
              // engine's time limit (the next run follows within seconds) or
              // the notification's Pause: stay `running`, save the bytes, and
              // let the guard ask the engine again.
              _log(
                '${d.videoId} engine paused, not by the app -> keeping running '
                '(guard armed) bytes=$done/${d.totalBytes ?? "?"}',
              );
              await _store.put(
                d.copyWith(
                  status: DownloadStatus.running,
                  downloadedBytes: done,
                  updatedAt: _clock(),
                ),
              );
              _armStallGuard(d.videoId);
            }
          case DownloaderState.complete:
            _clearTimers(d.videoId);
            await _complete(d);
          case DownloaderState.canceled:
            _clearTimers(d.videoId);
            _setProgress(d.videoId, null);
            await _onCanceled(d);
          case DownloaderState.failed:
            _clearTimers(d.videoId);
            final done = _currentBytes(d);
            _setProgress(d.videoId, null);
            await _failed(d.copyWith(downloadedBytes: done), event);
        }
    }
  }

  /// A `canceled` the app didn't cause is the notification's Cancel: the
  /// user threw the download away, so it's removed like an in-app cancel.
  /// The engine is asked first, so a task that runs again (a new attempt
  /// under the same ID) is never removed.
  Future<void> _onCanceled(Download d) async {
    if (!d.status.isActive) return;
    if (_within(_internalCancelAt, d.videoId, internalCancelWindow)) return;
    final state = (await _downloader.known())[d.videoId]?.state;
    if (state != null && state != DownloaderState.canceled) return;
    _log('${d.videoId} canceled outside the app -> removing');
    await _delete(d.videoId);
  }

  Future<void> _complete(Download d) async {
    _setProgress(d.videoId, null);
    _forget(d.videoId);
    _clearMissing(d.videoId);
    final videoPath = await _downloader.pathOf(_spot(d));
    int? size;
    try {
      size = await File(videoPath).length();
    } on FileSystemException {
      size = d.totalBytes;
    }
    await scanMediaFile(videoPath);
    final now = _clock();
    _log('${d.videoId} ${d.status.name} -> complete bytes=${size ?? "?"}');
    await _store.put(
      d.copyWith(
        status: DownloadStatus.complete,
        totalBytes: size,
        downloadedBytes: size ?? d.downloadedBytes,
        pausedByUser: false,
        startedOver: false,
        updatedAt: now,
        completedAt: now,
        clearProblem: true,
      ),
    );
    await _sweep();
  }

  Future<void> _failed(Download d, DownloaderStatus e) async {
    final code = e.httpCode;

    // The user paused it: no automatic retry overrides that.
    if (d.status == DownloadStatus.paused && d.pausedByUser) {
      await _failFromStatus(d, e);
      return;
    }

    // HTTP 401/403 (expired signed link): fetch fresh URL and resume once.
    if ((code == 401 || code == 403) && _autoRetried.add(d.videoId)) {
      _log('${d.videoId} HTTP $code -> auto-retrying with fresh URL');
      await _resume(d.videoId, automatic: true);
      return;
    }

    // "Task timed out": shouldn't happen in foreground mode; retry once.
    if (e.timedOut && _timeoutRetried.add(d.videoId)) {
      _log('${d.videoId} timed out -> auto-retrying once');
      await _resume(d.videoId, automatic: true);
      return;
    }

    // HTTP 416 or ETag/resume mismatch: delete temp file and restart from 0.
    if ((code == 416 || e.resumeError) && _restartRetried.add(d.videoId)) {
      _log(
        '${d.videoId} resume error (HTTP ${code ?? "-"}) -> restarting from 0',
      );
      await _resume(d.videoId, forceRestart: true, automatic: true);
      return;
    }

    // HTTP 5xx: retry with exponential backoff up to 3 times.
    if (code != null && code >= 500 && code < 600) {
      final attempt = (_serverRetries[d.videoId] ?? 0) + 1;
      if (attempt <= 3) {
        _serverRetries[d.videoId] = attempt;
        final delay = serverRetryBaseDelay * (1 << (attempt - 1));
        _log(
          '${d.videoId} HTTP $code -> scheduling server retry $attempt/3 '
          'in ${delay.inSeconds}s',
        );
        await _store.put(
          d.copyWith(status: DownloadStatus.queued, updatedAt: _clock()),
        );
        _retryTimers.remove(d.videoId)?.cancel();
        _retryTimers[d.videoId] = Timer(delay, () {
          _retryTimers.remove(d.videoId);
          if (!_disposed) {
            unawaited(_serial(() => _resume(d.videoId, automatic: true)));
          }
        });
        return;
      }
    }

    await _failFromStatus(d, e);
  }

  Future<void> _failFromStatus(Download d, DownloaderStatus e) {
    final code = e.httpCode;
    final problem = e.noSpace
        ? DownloadProblem.noSpace
        : e.fileError
        ? DownloadProblem.storage
        : e.timedOut
        ? DownloadProblem.interrupted
        : (code == 401 || code == 403)
        ? DownloadProblem.linkExpired
        : (code == 404 || code == 410)
        ? DownloadProblem.unavailable
        : (code != null && code >= 500 && code < 600)
        ? DownloadProblem.server
        : (e.connectionError || code == null)
        ? DownloadProblem.network
        : DownloadProblem.unknown;
    return _fail(d, problem, detail: e.detail);
  }

  Future<void> _fail(
    Download d,
    DownloadProblem problem, {
    String? detail,
  }) async {
    _clearTimers(d.videoId);
    _lastProgressSavedAt.remove(d.videoId);
    _log(
      '${d.videoId} ${d.status.name} -> failed reason=${problem.name} '
      'bytes=${d.downloadedBytes}/${d.totalBytes ?? "?"}'
      '${detail == null ? "" : " detail=$detail"}',
    );
    await _store.put(
      d.copyWith(
        status: DownloadStatus.failed,
        problem: problem,
        problemDetail: detail,
        pausedByUser: false,
        updatedAt: _clock(),
      ),
    );
    await _sweep();
    if (passingProblems.contains(problem)) _scheduleSlowRetry(d.videoId);
  }

  static FileSpot _spot(Download d) =>
      FileSpot(d.baseDirectory, d.directory, d.fileName);

  static int _height(String quality) =>
      int.tryParse(RegExp(r'\d{3,4}').firstMatch(quality)?[0] ?? '') ?? 1080;

  static String _two(int n) => n.toString().padLeft(2, '0');
}

final downloadStoreProvider = Provider<DownloadStore>(
  (ref) => DriftDownloadStore(ref.watch(appDatabaseProvider)),
);

/// Where new downloads go, asked at each download (the desktop folder can
/// change). Tests point it at a temporary folder.
final downloadRootProvider = Provider<Future<DownloadRoot> Function()>(
  (ref) =>
      () => platformDownloadRoot(ref.read(settingsProvider).downloadFolder),
);

final downloaderProvider = Provider<Downloader>(
  (ref) => BackgroundFileDownloader(),
);

/// Downloads for the whole app session (never disposed: it follows the
/// engine's events). Tests override [downloadStoreProvider] and
/// [downloaderProvider].
final downloadsRepositoryProvider = Provider<DownloadsRepository>((ref) {
  final repo = DownloadsRepository(
    store: ref.watch(downloadStoreProvider),
    downloader: ref.watch(downloaderProvider),
    media: ref.watch(mediaRepositoryProvider),
    api: ref.watch(apiClientProvider),
    root: ref.watch(downloadRootProvider),
    connectivity: ref.watch(connectivityMonitorProvider),
    styledSubtitles: !isAndroid,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final downloadsProvider = StreamProvider<List<Download>>(
  (ref) => ref.watch(downloadsRepositoryProvider).watchAll(),
);

final downloadProgressProvider = StreamProvider<Map<String, DownloadProgress>>(
  (ref) => ref.watch(downloadsRepositoryProvider).watchProgress(),
);

final downloadMissingProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(downloadsRepositoryProvider).watchMissing(),
);

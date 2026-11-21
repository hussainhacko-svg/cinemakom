import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/platform_info.dart';
import 'downloader.dart';

/// [Downloader] on background_downloader: WorkManager / UIDT on Android,
/// URLSession on iOS, an isolate on desktop. The only file that imports it.
class BackgroundFileDownloader implements Downloader {
  BackgroundFileDownloader([FileDownloader? downloader])
    : _fd = downloader ?? FileDownloader();

  final FileDownloader _fd;
  final _events = StreamController<DownloaderEvent>.broadcast();
  final _taps = StreamController<String>.broadcast();
  bool _started = false;
  String? _partialDir;

  /// Fail a download when less than this would be left free (MB).
  static const spaceReserveMb = downloadSpaceReserveMb;

  /// How often a dropped connection is retried before the task fails
  /// (docs/DOWNLOADS.md §5.1, §5.5: max 10, exponential 2 s to 512 s).
  static const retries = 10;

  @override
  Stream<DownloaderEvent> get events => _events.stream;

  @override
  Stream<String> get notificationTaps => _taps.stream;

  @override
  Future<void> start({String? partialDir, int maxRunning = 2}) async {
    if (_started) return;
    _started = true;
    _partialDir = partialDir;
    await _fd.configure(
      globalConfig: [
        (Config.holdingQueue, (maxRunning, null, null)),
        (Config.checkAvailableSpace, spaceReserveMb),
      ],
      // Multi-GB files: keep partial files on the same external volume as
      // Movies/Cinemakom so finishing is a rename, and run every Android
      // download in a foreground service (docs/DOWNLOADS.md §5.1, §5.6).
      androidConfig: [
        (Config.useCacheDir, Config.never),
        (Config.runInForeground, Config.always),
        if (partialDir != null) (Config.tempFilePath, partialDir),
      ],
      // /tmp is often RAM (tmpfs); keep partial files on the target disk.
      desktopConfig: [
        if (partialDir != null) (Config.tempFilePath, partialDir),
      ],
    );
    _fd.registerCallbacks(
      taskNotificationTapCallback: (task, type) => _taps.add(task.taskId),
    );
    // Lives as long as the app (the service is never disposed).
    _fd.updates.listen(_onUpdate);
    // Tracks tasks in its database, reconciles what finished while the app
    // was closed, and reschedules tasks the OS killed.
    await _fd.start();
  }

  static DownloaderStatus _statusFrom(
    String id,
    TaskStatus status,
    TaskException? exception, {
    int? responseStatusCode,
  }) {
    final http = exception is TaskHttpException
        ? exception.httpResponseCode
        : responseStatusCode;
    final description = exception?.description.toLowerCase() ?? '';
    final isSpace =
        exception is TaskFileSystemException && description.contains('space');
    final isTimedOut = description.contains('timed out');
    return DownloaderStatus(
      id,
      _state(status),
      httpCode: http != null && http > 0 ? http : null,
      noSpace: isSpace,
      fileError: exception is TaskFileSystemException && !isSpace,
      connectionError: exception is TaskConnectionException && !isTimedOut,
      resumeError: exception is TaskResumeException,
      timedOut: isTimedOut,
      detail: exception?.toString(),
    );
  }

  void _onUpdate(TaskUpdate update) {
    final id = update.task.taskId;
    switch (update) {
      case TaskStatusUpdate(:final status, :final exception):
        _events.add(
          _statusFrom(
            id,
            status,
            exception,
            responseStatusCode: update.responseStatusCode,
          ),
        );
      case TaskProgressUpdate(:final progress):
        // Negative progress values are status signals (failed, paused, …),
        // already sent as status updates.
        if (progress < 0) return;
        _events.add(
          DownloaderProgress(
            id,
            fraction: progress.clamp(0, 1).toDouble(),
            expectedBytes: update.hasExpectedFileSize
                ? update.expectedFileSize
                : null,
            bytesPerSecond: update.hasNetworkSpeed
                ? update.networkSpeed * 1024 * 1024
                : null,
            timeLeft: update.hasTimeRemaining ? update.timeRemaining : null,
          ),
        );
    }
  }

  static DownloaderState _state(TaskStatus s) => switch (s) {
    TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloaderState.queued,
    TaskStatus.running => DownloaderState.running,
    TaskStatus.paused => DownloaderState.paused,
    TaskStatus.complete => DownloaderState.complete,
    TaskStatus.canceled => DownloaderState.canceled,
    TaskStatus.failed || TaskStatus.notFound => DownloaderState.failed,
  };

  @override
  Future<void> setNotices(DownloadNotices n) async {
    _fd.configureNotification(
      running: TaskNotification(
        '{displayName}',
        '${n.running} · {progress} · {networkSpeed} · {timeRemaining}',
      ),
      complete: TaskNotification('{displayName}', n.complete),
      error: TaskNotification('{displayName}', n.failed),
      paused: TaskNotification('{displayName}', '${n.paused} · {progress}'),
      progressBar: true,
    );
  }

  @override
  Future<void> askToNotify() async {
    if (!isTouchMobile) return;
    final permissions = _fd.permissions;
    if (await permissions.status(PermissionType.notifications) !=
        PermissionStatus.granted) {
      await permissions.request(PermissionType.notifications);
    }
  }

  DownloadTask _task(DownloadJob job) => DownloadTask(
    taskId: job.taskId,
    url: job.url,
    headers: job.headers,
    baseDirectory: _base(job.spot.baseDirectory),
    directory: job.spot.directory,
    filename: job.spot.fileName,
    displayName: job.displayName,
    updates: Updates.statusAndProgress,
    retries: retries,
    // Pausable (also across Android's 9-minute work limit) and, with a
    // notification, a user-initiated transfer on Android 14+.
    transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
  );

  static BaseDirectory _base(String name) =>
      BaseDirectory.values.asNameMap()[name] ?? BaseDirectory.root;

  @override
  Future<bool> enqueue(DownloadJob job) async {
    // A task with this ID may linger from an earlier attempt.
    await _fd.database.deleteRecordWithId(job.taskId);
    final task = _task(job);
    if (job.notice case final n?) {
      _fd.configureNotificationForTask(
        task,
        running: TaskNotification(n.runningTitle, n.runningBody),
        paused: TaskNotification(n.pausedTitle, n.pausedBody),
        complete: TaskNotification(n.completeTitle, n.completeBody),
        error: TaskNotification(n.errorTitle, n.errorBody),
        progressBar: true,
      );
    }
    return _fd.enqueue(task);
  }

  Future<DownloadTask?> _known(String taskId) async {
    final task =
        await _fd.taskForId(taskId) ??
        (await _fd.database.recordForId(taskId))?.task;
    return task is DownloadTask ? task : null;
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = await _known(taskId);
    return task != null && await _fd.pause(task);
  }

  @override
  Future<bool> resume(String taskId, String url) async {
    final task = await _known(taskId);
    if (task == null) return false;
    // Resume sends the task it's given, so the partial file continues from
    // the fresh signed URL (docs/PLAN.md Phase 6).
    return _fd.resume(task.copyWith(url: url));
  }

  @override
  Future<void> cancel(String taskId) async {
    await _fd.cancelTaskWithId(taskId);
    await _fd.database.deleteRecordWithId(taskId);
  }

  @override
  Future<bool> canResume(String taskId) async {
    final task = await _known(taskId);
    return task != null && await _fd.taskCanResume(task);
  }

  @override
  Future<void> sync() => _fd.resumeFromBackground();

  @override
  Future<Map<String, KnownTask>> known() async {
    final out = <String, KnownTask>{};
    for (final r in await _fd.database.allRecords()) {
      final state = _state(r.status);
      out[r.taskId] = KnownTask(
        state,
        fraction: r.progress >= 0 ? r.progress.clamp(0, 1).toDouble() : null,
        expectedBytes: r.expectedFileSize > 0 ? r.expectedFileSize : null,
        failure: state == DownloaderState.failed
            ? _statusFrom(r.taskId, r.status, r.exception)
            : null,
      );
    }
    // Also check active native & holding-queue tasks (docs/DOWNLOADS.md §5.4).
    for (final t in await _fd.allTasks(allGroups: true)) {
      final existing = out[t.taskId];
      if (existing == null ||
          existing.state == DownloaderState.paused ||
          existing.state == DownloaderState.failed ||
          existing.state == DownloaderState.canceled) {
        out[t.taskId] = KnownTask(
          DownloaderState.queued,
          fraction: existing?.fraction,
          expectedBytes: existing?.expectedBytes,
        );
      }
    }
    return out;
  }

  @override
  Future<List<String>> tempDirs() async {
    final dirs = <String>{};
    if (_partialDir != null) dirs.add(_partialDir!);
    if (isMobile) {
      try {
        dirs.add((await getApplicationSupportDirectory()).path);
      } on Object {
        // Ignore if unavailable.
      }
    }
    if (isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) dirs.add(ext.path);
      } on Object {
        // Ignore if unavailable.
      }
    }
    return dirs.toList();
  }

  @override
  Future<String> pathOf(FileSpot spot) => DownloadTask(
    url: 'https://localhost',
    baseDirectory: _base(spot.baseDirectory),
    directory: spot.directory,
    filename: spot.fileName,
  ).filePath();
}

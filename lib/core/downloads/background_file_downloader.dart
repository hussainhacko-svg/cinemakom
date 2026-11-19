import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import '../platform/platform_info.dart';
import 'downloader.dart';

/// [Downloader] on background_downloader: WorkManager / UIDT on Android,
/// URLSession on iOS, an isolate on desktop. The only file that imports it.
class BackgroundFileDownloader implements Downloader {
  BackgroundFileDownloader([FileDownloader? downloader])
    : _fd = downloader ?? FileDownloader();

  final FileDownloader _fd;
  final _events = StreamController<DownloaderEvent>.broadcast();
  bool _started = false;

  /// Fail a download when less than this would be left free (MB).
  static const spaceReserveMb = 500;

  /// How often a dropped connection is retried before the task fails.
  static const retries = 3;

  @override
  Stream<DownloaderEvent> get events => _events.stream;

  @override
  Future<void> start({String? partialDir, int maxRunning = 2}) async {
    if (_started) return;
    _started = true;
    await _fd.configure(
      globalConfig: [
        (Config.holdingQueue, (maxRunning, null, null)),
        (Config.checkAvailableSpace, spaceReserveMb),
      ],
      // Multi-GB files: the cache dir can be evicted, and its quota is
      // small (CONFIG.md, useCacheDir).
      androidConfig: [(Config.useCacheDir, Config.never)],
      // /tmp is often RAM (tmpfs); keep partial files on the target disk.
      desktopConfig: [
        if (partialDir != null) (Config.tempFilePath, partialDir),
      ],
    );
    // Lives as long as the app (the service is never disposed).
    _fd.updates.listen(_onUpdate);
    // Tracks tasks in its database, reconciles what finished while the app
    // was closed, and reschedules tasks the OS killed.
    await _fd.start();
  }

  void _onUpdate(TaskUpdate update) {
    final id = update.task.taskId;
    switch (update) {
      case TaskStatusUpdate(:final status, :final exception):
        final http = exception is TaskHttpException
            ? exception.httpResponseCode
            : update.responseStatusCode;
        final description = exception?.description.toLowerCase() ?? '';
        _events.add(
          DownloaderStatus(
            id,
            _state(status),
            httpCode: http != null && http > 0 ? http : null,
            noSpace:
                exception is TaskFileSystemException &&
                description.contains('space'),
            fileError:
                exception is TaskFileSystemException &&
                !description.contains('space'),
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
      running: TaskNotification(n.running, '{displayName}'),
      complete: TaskNotification(n.complete, '{displayName}'),
      error: TaskNotification(n.failed, '{displayName}'),
      paused: TaskNotification(n.paused, '{displayName}'),
      progressBar: true,
    );
  }

  @override
  Future<void> askToNotify() async {
    if (!isMobile) return;
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
    return _fd.enqueue(_task(job));
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
  Future<Map<String, DownloaderState>> known() async => {
    for (final r in await _fd.database.allRecords()) r.taskId: _state(r.status),
  };

  @override
  Future<String> pathOf(FileSpot spot) => DownloadTask(
    url: 'https://localhost',
    baseDirectory: _base(spot.baseDirectory),
    directory: spot.directory,
    filename: spot.fileName,
  ).filePath();
}

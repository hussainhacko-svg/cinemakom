import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// The one exception to core not reaching into data: the URL refresh runs in
// the engine's callback isolate and needs the streams endpoint and parser.
import '../../data/repositories/download_url_refresh.dart';
import '../platform/platform_info.dart';
import 'downloader.dart';
import 'kept_resume_store.dart';

/// [Downloader] on background_downloader: WorkManager / UIDT on Android,
/// URLSession on iOS, an isolate on desktop. The only file that imports it.
///
/// Two additions for slow connections and huge files (docs/DOWNLOADS.md
/// §5.5): resume data survives a final failure ([KeptResumeStore]), and a
/// URL about to expire is replaced before each run ([refreshSignedUrl]).
class BackgroundFileDownloader implements Downloader {
  /// [retries]: how often a dropped connection is retried before the task
  /// fails (docs/DOWNLOADS.md §5.1, §5.5: the library's maximum, 10,
  /// exponential 2 s to 512 s). Tests lower it.
  BackgroundFileDownloader({this.retries = 10});

  final int retries;

  // background_downloader is one engine per process, and it takes its
  // storage only on its first construction: every instance shares both.
  static final _storage = _MirroredStorage();
  static final _fd = FileDownloader(persistentStorage: _storage);
  final _kept = KeptResumeStore(
    () async => p.join(
      (await getApplicationSupportDirectory()).path,
      'cinemakom_kept_resume.json',
    ),
  );
  final _events = StreamController<DownloaderEvent>.broadcast();
  final _taps = StreamController<String>.broadcast();
  bool _started = false;
  String? _partialDir;

  /// Fail a download when less than this would be left free (MB).
  static const spaceReserveMb = downloadSpaceReserveMb;

  @override
  Stream<DownloaderEvent> get events => _events.stream;

  @override
  Stream<String> get notificationTaps => _taps.stream;

  @override
  Future<void> start({String? partialDir, int maxRunning = 2}) async {
    if (_started) return;
    _started = true;
    _partialDir = partialDir;
    await _storage.loadMirror();
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

  /// The engine's status as the app's. The exception's type isn't always
  /// right: on desktop a refused or dropped connection arrives as a
  /// `TaskFileSystemException` ("ClientException with SocketException"),
  /// and on Android every `IOException` but a socket one does (an unknown
  /// host, a TLS error, a stream cut short). Those would read "Couldn't
  /// save the file" and never continue by themselves, so the description is
  /// checked for network errors too ([networkErrors]).
  @visibleForTesting
  static DownloaderStatus statusFrom(
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
        exception is TaskFileSystemException &&
        _spaceErrors.any(description.contains);
    final isTimedOut = description.contains('timed out');
    final isNetwork =
        exception is TaskConnectionException ||
        networkErrors.any(description.contains);
    return DownloaderStatus(
      id,
      _state(status),
      httpCode: http != null && http > 0 ? http : null,
      noSpace: isSpace,
      fileError: exception is TaskFileSystemException && !isSpace && !isNetwork,
      connectionError: isNetwork && !isTimedOut,
      resumeError: exception is TaskResumeException,
      timedOut: isTimedOut,
      detail: exception?.toString(),
    );
  }

  /// What a network error's description contains (lower case): Dart's
  /// (desktop) and Java's (Android, `e.toString()`).
  @visibleForTesting
  static const networkErrors = [
    'socketexception',
    'clientexception',
    'httpexception',
    'handshakeexception',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection abort',
    'network is unreachable',
    'failed host lookup',
    'unknownhostexception',
    'sslexception',
    'eofexception',
    // Android: javax.net.ssl.SSLProtocolException, java.net.ProtocolException
    // ("unexpected end of stream"), HTTP/2's StreamResetException.
    'protocolexception',
    'unexpected end of stream',
    'streamresetexception',
    'connectexception',
    'noroutetohostexception',
  ];

  /// A full disk, by platform: the engine's own check (Android), ENOSPC
  /// (Android, Linux), Windows' error 112. Not just "space": a folder may
  /// be called that.
  static const _spaceErrors = [
    'insufficient space',
    'no space left',
    'enospc',
    'not enough space',
    'disk full',
    'disk is full',
  ];

  /// A progress update as the app's, or `null` for the negative values the
  /// engine uses as status signals (failed, paused, …), which come as
  /// status updates too. `networkSpeed` is in MB/s.
  @visibleForTesting
  static DownloaderProgress? progressFrom(TaskProgressUpdate update) {
    if (update.progress < 0) return null;
    return DownloaderProgress(
      update.task.taskId,
      fraction: update.progress.clamp(0, 1).toDouble(),
      expectedBytes: update.hasExpectedFileSize
          ? update.expectedFileSize
          : null,
      bytesPerSecond: update.hasNetworkSpeed
          ? update.networkSpeed * 1024 * 1024
          : null,
      timeLeft: update.hasTimeRemaining ? update.timeRemaining : null,
    );
  }

  void _onUpdate(TaskUpdate update) {
    final id = update.task.taskId;
    switch (update) {
      case TaskStatusUpdate(:final status, :final exception):
        // The engine has just cleared this task's resume data. A failure
        // keeps it for Retry; a finished or cancelled task needs none.
        if (status.isFinalState) {
          final cleared = _storage.takeCleared(id);
          if (status == TaskStatus.failed && cleared != null) {
            unawaited(_keep(cleared));
          } else if (status != TaskStatus.failed) {
            unawaited(_kept.remove(id));
          }
        }
        _events.add(
          statusFrom(
            id,
            status,
            exception,
            responseStatusCode: update.responseStatusCode,
          ),
        );
      case TaskProgressUpdate():
        if (progressFrom(update) case final progress?) _events.add(progress);
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
  Future<void> askForStorage() async {
    if (!isAndroid) return;
    // Only Android 7–9 asks (WRITE_EXTERNAL_STORAGE); later versions answer
    // granted without a dialog.
    final permissions = _fd.permissions;
    const type = PermissionType.androidSharedStorage;
    try {
      if (await permissions.status(type) != PermissionStatus.granted) {
        await permissions.request(type);
      }
    } on Object {
      // Without it, downloads stay in the app's folder (§5.6).
    }
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
    metaData: job.quality ?? '',
    options: refreshOptions(job.url, job.quality),
    // Pausable (also across Android's 9-minute work limit) and, with a
    // notification, a user-initiated transfer on Android 14+.
    transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
  );

  /// The engine's `Auth` hook as a URL refresh: it compares the "token"
  /// expiry, [downloadUrlRefreshMargin] before the URL's `Expires`, before
  /// every run (its own retries, rescheduled tasks, resumes) and only then
  /// calls [refreshSignedUrl]. No access parameters: the URL is left as is.
  @visibleForTesting
  static TaskOptions? refreshOptions(String url, String? quality) {
    final expires = signedUrlExpiry(url);
    if (expires == null || quality == null || quality.isEmpty) return null;
    return TaskOptions(
      auth: Auth(
        accessTokenExpiryTime: expires.subtract(downloadUrlRefreshMargin),
        onAuth: refreshSignedUrl,
      ),
    );
  }

  /// Keeps the resume data a final failure cleared (see [KeptResumeStore]).
  /// Only a partial file on disk can be continued: iOS's resume data is
  /// URLSession's own and isn't a path.
  Future<void> _keep(ResumeData d) => _kept.keep(
    d.task.taskId,
    d.toJson(),
    tempPath: d.data,
    startByte: d.requiredStartByte,
  );

  /// Gives a failed task back its kept resume data, when the engine has
  /// none and the partial file is still whole. True when it can resume.
  Future<bool> _restoreKept(String taskId) async {
    if (await _storage.retrieveResumeData(taskId) != null) return true;
    final json = await _kept.usable(taskId);
    if (json == null) return false;
    try {
      await _storage.storeResumeData(ResumeData.fromJson(json));
      return true;
    } on Object {
      await _kept.remove(taskId);
      return false;
    }
  }

  static BaseDirectory _base(String name) =>
      BaseDirectory.values.asNameMap()[name] ?? BaseDirectory.root;

  @override
  Future<bool> enqueue(DownloadJob job) async {
    // A task with this ID may linger from an earlier attempt.
    await _fd.database.deleteRecordWithId(job.taskId);
    final task = _task(job);
    _configureNotice(task, job.notice);
    return _fd.enqueue(task);
  }

  /// The per-task notification (§5.9). background_downloader keeps these in
  /// memory only, so a resume after a restart sets it again.
  void _configureNotice(Task task, DownloadTaskNotice? n) {
    if (n == null) return;
    _fd.configureNotificationForTask(
      task,
      running: TaskNotification(n.runningTitle, n.runningBody),
      paused: TaskNotification(n.pausedTitle, n.pausedBody),
      complete: TaskNotification(n.completeTitle, n.completeBody),
      error: TaskNotification(n.errorTitle, n.errorBody),
      progressBar: true,
    );
  }

  Future<DownloadTask?> _known(String taskId) async {
    final task =
        await _fd.taskForId(taskId) ??
        (await _fd.database.recordForId(taskId))?.task ??
        (await _storage.retrieveResumeData(taskId))?.task;
    return task is DownloadTask ? task : null;
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = await _known(taskId);
    return task != null && await _fd.pause(task);
  }

  @override
  Future<bool> resume(
    String taskId,
    String url, {
    DownloadTaskNotice? notice,
  }) async {
    final restored = await _restoreKept(taskId);
    final task = await _known(taskId);
    if (task == null || !restored) return false;
    _configureNotice(task, notice);
    // Resume sends the task it's given, so the partial file continues from
    // the fresh signed URL (docs/PLAN.md Phase 6), with every retry again
    // and the URL refresh set for the new URL.
    final ok = await _fd.resume(
      task.copyWith(
        url: url,
        retriesRemaining: retries,
        options: refreshOptions(url, task.metaData),
      ),
    );
    if (ok) await _kept.remove(taskId);
    return ok;
  }

  @override
  Future<void> cancel(String taskId) async {
    await _kept.remove(taskId);
    await _fd.cancelTaskWithId(taskId);
    await _fd.database.deleteRecordWithId(taskId);
  }

  /// Read from the storage rather than `taskCanResume`, which waits for a
  /// task in the holding queue to start (it could hang forever).
  @override
  Future<bool> canResume(String taskId) async =>
      await _storage.retrieveResumeData(taskId) != null ||
      await _kept.usable(taskId) != null;

  @override
  Future<Map<String, String>> protectedTempFiles(Set<String> taskIds) async => {
    ...await _kept.tempPaths(taskIds),
    for (final d in await _storage.retrieveAllResumeData())
      if (taskIds.contains(d.task.taskId)) d.task.taskId: d.data,
  };

  @override
  Future<void> sync() => _fd.resumeFromBackground();

  @override
  Future<Map<String, KnownTask>> known() async => knownFrom(
    await _fd.database.allRecords(),
    await _fd.allTasks(allGroups: true),
  );

  /// What the engine knows: its database [records], and the [live] tasks
  /// of its native and holding queues and those waiting to retry
  /// (docs/DOWNLOADS.md §5.4).
  @visibleForTesting
  static Map<String, KnownTask> knownFrom(
    List<TaskRecord> records,
    List<Task> live,
  ) {
    final out = <String, KnownTask>{};
    for (final r in records) {
      final state = _state(r.status);
      out[r.taskId] = KnownTask(
        state,
        fraction: r.progress >= 0 ? r.progress.clamp(0, 1).toDouble() : null,
        expectedBytes: r.expectedFileSize > 0 ? r.expectedFileSize : null,
        failure: state == DownloaderState.failed
            ? statusFrom(r.taskId, r.status, r.exception)
            : null,
      );
    }
    // `allTasks` lists paused tasks too, so a paused (or finished) record
    // keeps its state: only a task without a live record counts as queued
    // (PR #4 review, critical 3).
    for (final t in live) {
      final existing = out[t.taskId];
      if (existing == null ||
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

/// Before a run of a download whose signed URL is about to expire, asks the
/// API for a fresh one in the same quality (docs/DOWNLOADS.md §5.5). Called
/// by background_downloader's `Auth` hook from native code, in a background
/// isolate on Android: top level, an entry point, no app state. Any problem
/// keeps the old URL; the app's own 403 handling is the fallback.
@pragma('vm:entry-point')
Future<Task?> refreshSignedUrl(Task task) async {
  if (task is! DownloadTask || task.metaData.isEmpty) return null;
  try {
    final url = await freshDownloadUrl(
      task.taskId,
      task.metaData,
    ).timeout(const Duration(seconds: 20));
    if (url == null) return null;
    return task.copyWith(
      url: url,
      options: BackgroundFileDownloader.refreshOptions(url, task.metaData),
    );
  } on Object {
    return null;
  }
}

/// background_downloader's own storage, with an in-memory mirror of the
/// resume data, so what the engine clears on a final failure can still be
/// kept. The engine clears it synchronously before it sends the `failed`
/// update ([TaskStatus.isFinalState] in `processStatusUpdate`), so the
/// mirror always has it when the update arrives.
class _MirroredStorage implements PersistentStorage {
  final PersistentStorage _inner = LocalStorePersistentStorage();
  final _resume = <String, ResumeData>{};
  final _cleared = <String, ResumeData>{};
  bool _mirrored = false;

  Future<void> loadMirror() async {
    if (_mirrored) return;
    _mirrored = true;
    try {
      for (final d in await _inner.retrieveAllResumeData()) {
        _resume.putIfAbsent(d.task.taskId, () => d);
      }
    } on Object {
      // Nothing to mirror.
    }
  }

  /// The resume data the engine just cleared for [taskId], once.
  ResumeData? takeCleared(String taskId) => _cleared.remove(taskId);

  @override
  Future<void> initialize() async {
    await _inner.initialize();
    await loadMirror();
  }

  @override
  Future<void> storeResumeData(ResumeData resumeData) {
    _resume[resumeData.task.taskId] = resumeData;
    _cleared.remove(resumeData.task.taskId);
    return _inner.storeResumeData(resumeData);
  }

  @override
  Future<void> removeResumeData(String? taskId) {
    if (taskId == null) {
      _resume.clear();
    } else if (_resume.remove(taskId) case final d?) {
      _cleared[taskId] = d;
    }
    return _inner.removeResumeData(taskId);
  }

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) =>
      _inner.retrieveResumeData(taskId);

  @override
  Future<List<ResumeData>> retrieveAllResumeData() =>
      _inner.retrieveAllResumeData();

  @override
  Future<void> storeTaskRecord(TaskRecord record) =>
      _inner.storeTaskRecord(record);

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) =>
      _inner.retrieveTaskRecord(taskId);

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() =>
      _inner.retrieveAllTaskRecords();

  @override
  Future<void> removeTaskRecord(String? taskId) =>
      _inner.removeTaskRecord(taskId);

  @override
  Future<void> storePausedTask(Task task) => _inner.storePausedTask(task);

  @override
  Future<Task?> retrievePausedTask(String taskId) =>
      _inner.retrievePausedTask(taskId);

  @override
  Future<List<Task>> retrieveAllPausedTasks() =>
      _inner.retrieveAllPausedTasks();

  @override
  Future<void> removePausedTask(String? taskId) =>
      _inner.removePausedTask(taskId);

  @override
  (String, int) get currentDatabaseVersion => _inner.currentDatabaseVersion;

  @override
  Future<(String, int)> get storedDatabaseVersion =>
      _inner.storedDatabaseVersion;
}

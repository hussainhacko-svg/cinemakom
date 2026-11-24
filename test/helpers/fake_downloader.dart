import 'dart:async';
import 'dart:io';

import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:path/path.dart' as p;

/// A [Downloader] that records what it's asked and lets tests send the
/// engine's events. Paths resolve under [root] (a temporary folder).
class FakeDownloader implements Downloader {
  FakeDownloader({String? root})
    : root = root ?? Directory.systemTemp.createTempSync('dl').path;

  final String root;
  final _events = StreamController<DownloaderEvent>.broadcast();
  final _taps = StreamController<String>.broadcast();

  final enqueued = <DownloadJob>[];
  final paused = <String>[];
  final resumed = <(String, String)>[];

  /// The notification each [resume] was given, by task ID.
  final resumeNotices = <String, DownloadTaskNotice?>{};
  int storageAsks = 0;
  final canceled = <String>[];
  final knownStates = <String, DownloaderState>{};
  final knownFailures = <String, DownloaderStatus>{};
  final knownProgress = <String, (double, int?)>{};
  final tempDirectories = <String>[];

  /// What [protectedTempFiles] reports, by task ID.
  final protectedFiles = <String, String>{};
  int syncCalls = 0;
  bool started = false;
  DownloadNotices? notices;

  /// What [pause] answers (`false` simulates a task in the holding queue).
  bool pauseReturns = true;

  /// Per-task override for [pause].
  final pauseable = <String, bool>{};

  /// What [resume] and [canResume] answer (whether a partial file exists).
  bool resumeAllowed = true;

  /// Per-task override for [resume] and [canResume].
  final resumable = <String, bool>{};

  /// Backwards-compatible setter for tests that toggle `canResume = false`.
  set canResumeValue(bool value) => resumeAllowed = value;

  /// Sends an engine event, as background_downloader would.
  void send(DownloaderEvent event) => _events.add(event);

  /// Writes [job]'s file with [bytes] bytes and reports it complete.
  Future<void> finish(DownloadJob job, {int bytes = 1000}) async {
    final file = File(await pathOf(job.spot));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 0));
    knownStates[job.taskId] = DownloaderState.complete;
    send(DownloaderStatus(job.taskId, DownloaderState.complete));
  }

  /// Simulates the user tapping a system download notification.
  void tapNotification(String taskId) => _taps.add(taskId);

  @override
  Stream<DownloaderEvent> get events => _events.stream;

  @override
  Stream<String> get notificationTaps => _taps.stream;

  @override
  Future<void> start({String? partialDir, int maxRunning = 2}) async =>
      started = true;

  @override
  Future<void> setNotices(DownloadNotices notices) async =>
      this.notices = notices;

  @override
  Future<void> askToNotify() async => notifyDialog?.future;

  /// Set to hold [askToNotify] like the permission dialog does.
  Completer<void>? notifyDialog;

  @override
  Future<void> askForStorage() async => storageAsks++;

  @override
  Future<bool> enqueue(DownloadJob job) async {
    enqueued.add(job);
    knownStates[job.taskId] = DownloaderState.queued;
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    paused.add(taskId);
    final ok = pauseable[taskId] ?? pauseReturns;
    if (ok) knownStates[taskId] = DownloaderState.paused;
    return ok;
  }

  @override
  Future<bool> resume(
    String taskId,
    String url, {
    DownloadTaskNotice? notice,
  }) async {
    resumed.add((taskId, url));
    resumeNotices[taskId] = notice;
    final ok = resumable[taskId] ?? resumeAllowed;
    if (ok) knownStates[taskId] = DownloaderState.queued;
    return ok;
  }

  @override
  Future<void> cancel(String taskId) async {
    canceled.add(taskId);
    knownStates.remove(taskId);
    knownFailures.remove(taskId);
    knownProgress.remove(taskId);
  }

  @override
  Future<bool> canResume(String taskId) async =>
      resumable[taskId] ?? resumeAllowed;

  @override
  Future<void> sync() async => syncCalls++;

  @override
  Future<Map<String, KnownTask>> known() async => {
    for (final e in knownStates.entries)
      e.key: KnownTask(
        e.value,
        fraction: knownProgress[e.key]?.$1,
        expectedBytes: knownProgress[e.key]?.$2,
        failure: knownFailures[e.key],
      ),
  };

  @override
  Future<List<String>> tempDirs() async => List.of(tempDirectories);

  @override
  Future<Map<String, String>> protectedTempFiles(Set<String> taskIds) async => {
    for (final e in protectedFiles.entries)
      if (taskIds.contains(e.key)) e.key: e.value,
  };

  @override
  Future<String> pathOf(FileSpot spot) async => spot.baseDirectory == 'root'
      ? p.join(spot.directory, spot.fileName)
      : p.join(root, spot.baseDirectory, spot.directory, spot.fileName);
}

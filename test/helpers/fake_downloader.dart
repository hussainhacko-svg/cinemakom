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

  final enqueued = <DownloadJob>[];
  final paused = <String>[];
  final resumed = <(String, String)>[];
  final canceled = <String>[];
  final knownStates = <String, DownloaderState>{};
  bool started = false;
  DownloadNotices? notices;

  /// What [resume] answers (whether a partial file exists).
  bool canResume = true;

  /// Sends an engine event, as background_downloader would.
  void send(DownloaderEvent event) => _events.add(event);

  /// Writes [job]'s file with [bytes] bytes and reports it complete.
  Future<void> finish(DownloadJob job, {int bytes = 1000}) async {
    final file = File(await pathOf(job.spot));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 0));
    send(DownloaderStatus(job.taskId, DownloaderState.complete));
  }

  @override
  Stream<DownloaderEvent> get events => _events.stream;

  @override
  Future<void> start({String? partialDir, int maxRunning = 2}) async =>
      started = true;

  @override
  Future<void> setNotices(DownloadNotices notices) async =>
      this.notices = notices;

  @override
  Future<void> askToNotify() async {}

  @override
  Future<bool> enqueue(DownloadJob job) async {
    enqueued.add(job);
    knownStates[job.taskId] = DownloaderState.queued;
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    paused.add(taskId);
    knownStates[taskId] = DownloaderState.paused;
    return true;
  }

  @override
  Future<bool> resume(String taskId, String url) async {
    resumed.add((taskId, url));
    return canResume;
  }

  @override
  Future<void> cancel(String taskId) async {
    canceled.add(taskId);
    knownStates.remove(taskId);
  }

  @override
  Future<Map<String, DownloaderState>> known() async => Map.of(knownStates);

  @override
  Future<String> pathOf(FileSpot spot) async => spot.baseDirectory == 'root'
      ? p.join(spot.directory, spot.fileName)
      : p.join(root, spot.baseDirectory, spot.directory, spot.fileName);
}

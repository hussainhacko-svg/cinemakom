/// The download engine behind the downloads service, so tests can swap it
/// (like `PlayerEngine`). `background_file_downloader.dart` is the only file
/// that imports background_downloader.
library;

/// Where a file goes: a base directory as background_downloader names it
/// (`root` for an absolute [directory]), a folder in it, and a file name.
class FileSpot {
  const FileSpot(this.baseDirectory, this.directory, this.fileName);

  /// `BaseDirectory.name`: "root", "applicationSupport", …
  final String baseDirectory;
  final String directory;
  final String fileName;

  @override
  String toString() => 'FileSpot($baseDirectory, $directory, $fileName)';
}

/// A file to fetch in the background.
class DownloadJob {
  const DownloadJob({
    required this.taskId,
    required this.url,
    required this.headers,
    required this.spot,
    required this.displayName,
  });

  /// The movie's or episode's ID.
  final String taskId;
  final String url;
  final Map<String, String> headers;
  final FileSpot spot;

  /// Shown in the system notification.
  final String displayName;
}

enum DownloaderState {
  queued,
  running,
  paused,
  complete,

  /// Failed; [DownloaderStatus.httpCode] or [DownloaderStatus.noSpace] say
  /// why when known.
  failed,
  canceled,
}

sealed class DownloaderEvent {
  const DownloaderEvent(this.taskId);

  final String taskId;
}

class DownloaderStatus extends DownloaderEvent {
  const DownloaderStatus(
    super.taskId,
    this.state, {
    this.httpCode,
    this.noSpace = false,
    this.fileError = false,
    this.canResume = false,
  });

  final DownloaderState state;
  final int? httpCode;

  /// Failed because the disk would be too full.
  final bool noSpace;

  /// Failed writing the file.
  final bool fileError;

  /// A failed task kept its partial file, so [Downloader.resume] works.
  final bool canResume;

  @override
  String toString() => 'DownloaderStatus($taskId, ${state.name}'
      '${httpCode == null ? '' : ', HTTP $httpCode'})';
}

class DownloaderProgress extends DownloaderEvent {
  const DownloaderProgress(
    super.taskId, {
    required this.fraction,
    this.expectedBytes,
    this.bytesPerSecond,
    this.timeLeft,
  });

  final double fraction;
  final int? expectedBytes;
  final double? bytesPerSecond;
  final Duration? timeLeft;
}

/// The texts of the system notifications, in the UI language.
class DownloadNotices {
  const DownloadNotices({
    required this.running,
    required this.complete,
    required this.failed,
    required this.paused,
  });

  final String running;
  final String complete;
  final String failed;
  final String paused;
}

abstract interface class Downloader {
  /// Status and progress of every task, also those started before a
  /// restart (after [start]).
  Stream<DownloaderEvent> get events;

  /// Starts the engine: at most [maxRunning] at once, partial files under
  /// [partialDir] (desktop; null keeps the default), and a free-space
  /// reserve.
  Future<void> start({String? partialDir, int maxRunning = 2});

  Future<void> setNotices(DownloadNotices notices);

  /// Asks for the notification permission where one is needed.
  Future<void> askToNotify();

  Future<bool> enqueue(DownloadJob job);

  Future<bool> pause(String taskId);

  /// Continues [taskId] from its partial file with [url] (a fresh signed
  /// URL). `false` when there's nothing to continue from.
  Future<bool> resume(String taskId, String url);

  Future<void> cancel(String taskId);

  /// The tasks the engine still knows, by ID, with their last state.
  Future<Map<String, DownloaderState>> known();

  /// The absolute path of [spot].
  Future<String> pathOf(FileSpot spot);
}

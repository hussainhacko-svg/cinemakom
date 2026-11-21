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

/// Per-task system notification texts (docs/DOWNLOADS.md §5.9).
class DownloadTaskNotice {
  const DownloadTaskNotice({
    required this.runningTitle,
    required this.runningBody,
    required this.pausedTitle,
    required this.pausedBody,
    required this.completeTitle,
    required this.completeBody,
    required this.errorTitle,
    required this.errorBody,
  });

  final String runningTitle;
  final String runningBody;
  final String pausedTitle;
  final String pausedBody;
  final String completeTitle;
  final String completeBody;
  final String errorTitle;
  final String errorBody;
}

/// A file to fetch in the background.
class DownloadJob {
  const DownloadJob({
    required this.taskId,
    required this.url,
    required this.headers,
    required this.spot,
    required this.displayName,
    this.notice,
  });

  /// The movie's or episode's ID.
  final String taskId;
  final String url;
  final Map<String, String> headers;
  final FileSpot spot;

  /// Shown in the system notification.
  final String displayName;

  /// Per-task notification configuration (Android/iOS, §5.9).
  final DownloadTaskNotice? notice;
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
    this.connectionError = false,
    this.resumeError = false,
    this.timedOut = false,
    this.canResume = false,
    this.detail,
  });

  final DownloaderState state;
  final int? httpCode;

  /// Failed because the disk would be too full.
  final bool noSpace;

  /// Failed writing the file.
  final bool fileError;

  /// Failed due to a connection / socket exception.
  final bool connectionError;

  /// Failed resuming (ETag mismatch or missing temp file).
  final bool resumeError;

  /// Failed because the OS/engine timed out the task ("Task timed out").
  final bool timedOut;

  /// A failed task kept its partial file, so [Downloader.resume] works.
  final bool canResume;

  /// The engine's raw error description, for logs and Details. Never parsed.
  final String? detail;

  @override
  String toString() =>
      'DownloaderStatus($taskId, ${state.name}'
      '${httpCode == null ? '' : ', HTTP $httpCode'})';
}

/// Snapshot of a task the engine knows about (database + native/holding queue).
class KnownTask {
  const KnownTask(
    this.state, {
    this.fraction,
    this.expectedBytes,
    this.failure,
  });

  final DownloaderState state;
  final double? fraction;
  final int? expectedBytes;
  final DownloaderStatus? failure;
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
    this.waiting,
    this.formatSize,
    this.downloadedFolder,
    this.downloadedSize,
  });

  final String running;
  final String complete;
  final String failed;
  final String paused;
  final String? waiting;
  final String Function(int bytes)? formatSize;
  final String Function(String size)? downloadedFolder;
  final String Function(String size)? downloadedSize;
}

/// The free space a download never takes, in MB: the engine refuses to go
/// below it, and the TV's download panel offers only qualities that leave it.
const downloadSpaceReserveMb = 500;

abstract interface class Downloader {
  /// Status and progress of every task, also those started before a
  /// restart (after [start]).
  Stream<DownloaderEvent> get events;

  /// Task IDs whose system notification was tapped (docs/DOWNLOADS.md §5.9).
  Stream<String> get notificationTaps;

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

  /// Whether the engine currently has resume data for [taskId].
  Future<bool> canResume(String taskId);

  /// Delivers any status/progress updates accumulated while backgrounded.
  Future<void> sync();

  /// The tasks the engine still knows, by ID, from both its database and
  /// active/holding queues.
  Future<Map<String, KnownTask>> known();

  /// Directories where the engine stores temporary partial download files
  /// (`com.bbflight.background_downloader*`), used by [DownloadsJanitor].
  Future<List<String>> tempDirs();

  /// The absolute path of [spot].
  Future<String> pathOf(FileSpot spot);
}

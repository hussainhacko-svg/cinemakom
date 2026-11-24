import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/diagnostics/event_log.dart';

import '../../core/platform/app_dirs.dart';
import '../../core/platform/platform_info.dart';
import '../../core/platform/storage_space.dart';
import '../models/download.dart';
import '../models/media_item.dart';
import '../models/playback_models.dart';
import 'download_store.dart';

/// Where new downloads go: a base directory and a folder in it.
typedef DownloadRoot = ({String baseDirectory, String directory});

/// The default desktop download folder: `Cinemakom` in the user's videos
/// folder (`XDG_VIDEOS_DIR` on Linux, which may be translated or moved;
/// the Videos known folder on Windows, wherever the user put it).
String defaultDesktopFolder() {
  if (AppDirs.current case final dirs?) return p.join(dirs.videos, 'Cinemakom');
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return p.join(home, 'Videos', 'Cinemakom');
}

/// [name] as a safe file/folder name on every platform: no path separators or
/// characters Windows refuses, no leading dots (a hidden file on Linux and
/// Android, left out of the gallery), no trailing dots or spaces, not one of
/// Windows' device names (`CON`, `NUL`, `COM1`…), and at most [maxBytes]
/// bytes of UTF-8 (file systems allow 255; Arabic takes 2 bytes a letter),
/// leaving room for the ` (2)` and `.ar.srt` the caller may add.
String safeFileName(
  String name, {
  required String fallback,
  int maxBytes = maxNameBytes,
}) {
  var cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[. ]+'), '');
  cleaned = _truncateUtf8(cleaned, maxBytes).replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return fallback;
  return _windowsReserved.hasMatch(cleaned) ? '$cleaned _' : cleaned;
}

/// The longest file or folder name [safeFileName] makes, in bytes.
const maxNameBytes = 200;

final _windowsReserved = RegExp(
  r'^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(\..*)?$',
  caseSensitive: false,
);

/// [s] cut to at most [maxBytes] bytes of UTF-8, between whole characters.
String _truncateUtf8(String s, int maxBytes) {
  var bytes = 0;
  final out = StringBuffer();
  for (final rune in s.runes) {
    final size = rune < 0x80
        ? 1
        : rune < 0x800
        ? 2
        : rune < 0x10000
        ? 3
        : 4;
    if (bytes + size > maxBytes) break;
    bytes += size;
    out.writeCharCode(rune);
  }
  return out.toString();
}

/// Folder name for a movie or series: `<Title> (<Year>)` when year is known,
/// else `<Title>` (docs/DOWNLOADS.md §5.6).
String titleFolderName(MediaItem item, {required String fallback}) {
  final title = safeFileName(
    item.title.en ?? item.title.ar ?? fallback,
    fallback: fallback,
    maxBytes: maxNameBytes - 10,
  );
  final raw = (item.year != null && item.year! > 0)
      ? '$title (${item.year})'
      : title;
  return safeFileName(raw, fallback: fallback);
}

/// Base file name (without `.mp4`) for a movie or episode download
/// (docs/DOWNLOADS.md §5.6).
String videoFileStem(
  MediaItem item, {
  Episode? episode,
  required String quality,
  required String fallback,
}) {
  // The title gives way first, so the episode and quality always fit.
  final title = safeFileName(
    item.title.en ?? item.title.ar ?? fallback,
    fallback: fallback,
    maxBytes: maxNameBytes - 40,
  );
  String two(int n) => n.toString().padLeft(2, '0');
  return safeFileName(
    [
      title,
      if (episode != null)
        'S${two(episode.season)}E${two(episode.numbering.first)}'
            '${episode.numbering.last != episode.numbering.first ? '-E${two(episode.numbering.last)}' : ''}',
      quality,
    ].join(' '),
    fallback: fallback,
  );
}

/// Returns [stem] if `[directory]/[stem][ext]` is free, otherwise tries
/// `stem (2)`, `stem (3)`, ... so pre-existing user files are never overwritten
/// (docs/DOWNLOADS.md §5.6). Free means not on disk and not in [taken]
/// (paths as [takenKey] gives them): a download's file only appears when it
/// finishes, so the downloads on their way say which names are theirs.
String uniqueFileStem(
  String directory,
  String stem, {
  String ext = '.mp4',
  Set<String> taken = const {},
}) {
  bool free(String s) {
    final path = p.join(directory, '$s$ext');
    return !taken.contains(takenKey(path)) && !File(path).existsSync();
  }

  if (free(stem)) return stem;
  for (var n = 2; n < 1000; n++) {
    final candidate = '$stem ($n)';
    if (free(candidate)) return candidate;
  }
  return '$stem (${DateTime.now().millisecondsSinceEpoch})';
}

/// [path] as [uniqueFileStem]'s `taken` holds it. Without case, since
/// Android's shared storage and Windows ignore it: on Linux that only costs
/// a ` (2)` now and then.
String takenKey(String path) => p.normalize(path).toLowerCase();

/// Pure platform path resolution (unit-tested per platform and Android API
/// level in `test/data/download_paths_test.dart`, docs/DOWNLOADS.md §5.6).
DownloadRoot resolvePlatformDownloadRoot({
  required bool isDesktopPlatform,
  required bool isAndroidPlatform,
  String? desktopFolder,
  int? androidSdkInt,
  String? publicMoviesDir,
  bool hasLegacyStorage = false,
  String? externalAppDir,
}) {
  if (isDesktopPlatform) {
    return (
      baseDirectory: 'root',
      directory: desktopFolder ?? defaultDesktopFolder(),
    );
  }
  if (isAndroidPlatform) {
    final canUsePublic =
        publicMoviesDir != null &&
        ((androidSdkInt != null && androidSdkInt >= 29) || hasLegacyStorage);
    if (canUsePublic) {
      return (baseDirectory: 'root', directory: publicMoviesDir);
    }
    if (externalAppDir != null) {
      return (
        baseDirectory: 'root',
        directory: p.join(externalAppDir, 'Downloads'),
      );
    }
  }
  return (baseDirectory: 'applicationSupport', directory: 'Downloads');
}

/// Where new downloads go on this platform (docs/DOWNLOADS.md §5.6):
/// public `Movies/Cinemakom` on Android (falling back to app external storage
/// on API 24–28 without storage permission) and the chosen folder on
/// desktop.
Future<DownloadRoot> platformDownloadRoot(String? desktopFolder) async {
  if (isDesktop) {
    return resolvePlatformDownloadRoot(
      isDesktopPlatform: true,
      isAndroidPlatform: false,
      desktopFolder: desktopFolder,
    );
  }
  if (isAndroid) {
    final sdk = await androidSdkInt();
    final movies = await androidPublicMoviesDir();
    final legacyOk = await hasLegacyStoragePermission();
    final ext = await getExternalStorageDirectory();
    return resolvePlatformDownloadRoot(
      isDesktopPlatform: false,
      isAndroidPlatform: true,
      androidSdkInt: sdk,
      publicMoviesDir: movies,
      hasLegacyStorage: legacyOk,
      externalAppDir: ext?.path,
    );
  }
  return resolvePlatformDownloadRoot(
    isDesktopPlatform: false,
    isAndroidPlatform: false,
  );
}

/// Directory for partial download files on the same storage volume as the
/// destination so finishing is a rename, not a copy (docs/DOWNLOADS.md §5.6).
Future<String?> platformPartialDir(DownloadRoot root) async {
  if (isDesktop) {
    final dir = p.join(root.directory, '.partial');
    if (isWindows) await _hideOnWindows(dir);
    return dir;
  }
  if (isAndroid) {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return p.join(ext.path, '.partial');
    } on Object {
      // Fall back to default internal files dir.
    }
  }
  return null;
}

/// Legacy Phase 6 download root on Android (`Android/data/<pkg>/files/Downloads`).
Future<String?> legacyAndroidDownloadRoot() async {
  if (!isAndroid) return null;
  try {
    final ext = await getExternalStorageDirectory();
    return ext == null ? null : p.join(ext.path, 'Downloads');
  } on Object {
    return null;
  }
}

/// What [migrateLegacyDownloads] did.
typedef LegacyMigration = ({int moved, List<String> restarted});

/// Moves finished Phase 6 downloads from [legacyRoot] into [targetRoot]
/// (`Movies/Cinemakom`, docs/DOWNLOADS.md §5.6). Same-volume rename; if a
/// move fails the row keeps its existing path so nothing breaks.
///
/// Unfinished ones are broken anyway (§3): their engine task is cancelled
/// with [cancelTask], their row points into [targetRoot] with nothing saved,
/// and their IDs come back in `restarted` for the caller to start over.
Future<LegacyMigration> migrateLegacyDownloads({
  required DownloadStore store,
  required String legacyRoot,
  required String targetRoot,
  required Future<String> Function(Download) pathOf,
  Future<void> Function(String path)? onMoved,
  Future<void> Function(String videoId)? cancelTask,
}) async {
  final normLegacy = p.normalize(legacyRoot).toLowerCase();
  final normTarget = p.normalize(targetRoot).toLowerCase();
  if (normLegacy == normTarget) return (moved: 0, restarted: <String>[]);

  var movedCount = 0;
  final restarted = <String>[];
  final rows = await store.all();
  // Every row's path, updated as rows move: two never end up on one file.
  final taken = {for (final d in rows) takenKey(await pathOf(d))};
  for (final d in rows) {
    final oldPath = await pathOf(d);
    final normOld = p.normalize(oldPath).toLowerCase();
    if (!normOld.startsWith('$normLegacy${p.separator}')) continue;
    final oldDir = p.dirname(oldPath);
    final newDir = p.join(targetRoot, p.basename(oldDir));
    final ext = p.extension(d.fileName);
    final baseStem = p.basenameWithoutExtension(d.fileName);

    if (d.status != DownloadStatus.complete) {
      try {
        await cancelTask?.call(d.videoId);
        await Directory(newDir).create(recursive: true);
        final stem = uniqueFileStem(newDir, baseStem, ext: ext, taken: taken);
        taken.add(takenKey(p.join(newDir, '$stem$ext')));
        final subs = await _moveSubtitles(d, oldDir, newDir, baseStem, stem);
        await store.put(
          d.copyWith(
            baseDirectory: 'root',
            directory: newDir,
            fileName: '$stem$ext',
            subtitles: subs,
            status: DownloadStatus.failed,
            problem: DownloadProblem.interrupted,
            downloadedBytes: 0,
            pausedByUser: false,
          ),
        );
        restarted.add(d.videoId);
        logEvent('downloads', 'migrated unfinished ${d.videoId} -> $newDir');
        _removeIfEmpty(oldDir);
      } on FileSystemException catch (e) {
        logEvent('downloads', 'migration skipped for ${d.videoId}: $e');
      }
      continue;
    }

    final oldFile = File(oldPath);
    if (!oldFile.existsSync()) continue;
    try {
      await Directory(newDir).create(recursive: true);
      final uniqueStem = uniqueFileStem(
        newDir,
        baseStem,
        ext: ext,
        taken: taken,
      );
      final newFileName = '$uniqueStem$ext';
      taken.add(takenKey(p.join(newDir, newFileName)));
      final newVideoPath = p.join(newDir, newFileName);

      await _moveFile(oldFile, newVideoPath);
      final newSubs = await _moveSubtitles(
        d,
        oldDir,
        newDir,
        baseStem,
        uniqueStem,
      );

      await store.put(
        d.copyWith(
          baseDirectory: 'root',
          directory: newDir,
          fileName: newFileName,
          subtitles: newSubs,
        ),
      );
      if (onMoved != null) await onMoved(newVideoPath);
      movedCount++;
      logEvent('downloads', 'migrated ${d.videoId} -> $newVideoPath');
      _removeIfEmpty(oldDir);
    } on FileSystemException catch (e) {
      logEvent('downloads', 'migration skipped for ${d.videoId}: $e');
    }
  }
  return (moved: movedCount, restarted: restarted);
}

/// Moves [d]'s subtitles from [oldDir] to [newDir], renamed from [oldStem]
/// to [newStem]. One that can't move is left out.
Future<List<DownloadedSubtitle>> _moveSubtitles(
  Download d,
  String oldDir,
  String newDir,
  String oldStem,
  String newStem,
) async {
  final moved = <DownloadedSubtitle>[];
  for (final s in d.subtitles) {
    final oldSub = File(p.join(oldDir, s.fileName));
    if (!oldSub.existsSync()) continue;
    final suffix = s.fileName.startsWith(oldStem)
        ? s.fileName.substring(oldStem.length)
        : '.${s.language}.${s.format}';
    final name = '$newStem$suffix';
    try {
      await _moveFile(oldSub, p.join(newDir, name));
      moved.add(
        DownloadedSubtitle(
          language: s.language,
          fileName: name,
          format: s.format,
        ),
      );
    } on FileSystemException {
      // Keep the video even if a subtitle couldn't move.
    }
  }
  return moved;
}

void _removeIfEmpty(String path) {
  try {
    final dir = Directory(path);
    if (dir.existsSync() && dir.listSync(followLinks: false).isEmpty) {
      dir.deleteSync();
    }
  } on FileSystemException {
    // Ignore.
  }
}

Future<void> _moveFile(File src, String destPath) async {
  try {
    await src.rename(destPath);
  } on FileSystemException {
    await src.copy(destPath);
    await src.delete();
  }
}

/// A leading dot hides a folder on Linux, not on Windows: there the
/// unfinished downloads' folder gets the hidden attribute, so it doesn't
/// show in Videos.
Future<void> _hideOnWindows(String dir) async {
  try {
    await Directory(dir).create(recursive: true);
    await Process.run('attrib', ['+h', dir]);
  } on Object catch (e) {
    logEvent('downloads', "couldn't hide $dir: $e");
  }
}

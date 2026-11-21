import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/platform_info.dart';
import '../../core/platform/storage_space.dart';
import '../models/download.dart';
import '../models/media_item.dart';
import '../models/playback_models.dart';
import 'download_store.dart';

/// Where new downloads go: a base directory and a folder in it.
typedef DownloadRoot = ({String baseDirectory, String directory});

/// The default desktop download folder: `~/Videos/Cinemakom`.
String defaultDesktopFolder() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return p.join(home, 'Videos', 'Cinemakom');
}

/// [name] as a safe file/folder name on every platform: no path separators or
/// characters Windows refuses, no trailing dots or spaces.
String safeFileName(String name, {required String fallback}) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

/// Folder name for a movie or series: `<Title> (<Year>)` when year is known,
/// else `<Title>` (docs/DOWNLOADS.md §5.6).
String titleFolderName(MediaItem item, {required String fallback}) {
  final title = item.title.en ?? item.title.ar ?? fallback;
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
  final title = item.title.en ?? item.title.ar ?? fallback;
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

/// Returns [stem] if `[directory]/[stem][ext]` does not exist, otherwise tries
/// `stem (2)`, `stem (3)`, ... so pre-existing user files are never overwritten
/// (docs/DOWNLOADS.md §5.6).
String uniqueFileStem(String directory, String stem, {String ext = '.mp4'}) {
  if (!File(p.join(directory, '$stem$ext')).existsSync()) return stem;
  for (var n = 2; n < 1000; n++) {
    final candidate = '$stem ($n)';
    if (!File(p.join(directory, '$candidate$ext')).existsSync()) {
      return candidate;
    }
  }
  return '$stem (${DateTime.now().millisecondsSinceEpoch})';
}

/// Pure platform path resolution (unit-tested per platform and Android API
/// level in `test/data/download_paths_test.dart`, docs/DOWNLOADS.md §5.6).
DownloadRoot resolvePlatformDownloadRoot({
  required bool isDesktopPlatform,
  required bool isAndroidPlatform,
  required bool isIosPlatform,
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
  if (isIosPlatform) {
    // Visible in the iOS Files app with UIFileSharingEnabled (§5.6).
    return (baseDirectory: 'applicationDocuments', directory: 'Downloads');
  }
  return (baseDirectory: 'applicationSupport', directory: 'Downloads');
}

/// Where new downloads go on this platform (docs/DOWNLOADS.md §5.6):
/// public `Movies/Cinemakom` on Android (falling back to app external storage
/// on API 24–28 without storage permission), `Documents/Downloads` on iOS,
/// and the chosen folder on desktop.
Future<DownloadRoot> platformDownloadRoot(String? desktopFolder) async {
  if (isDesktop) {
    return resolvePlatformDownloadRoot(
      isDesktopPlatform: true,
      isAndroidPlatform: false,
      isIosPlatform: false,
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
      isIosPlatform: false,
      androidSdkInt: sdk,
      publicMoviesDir: movies,
      hasLegacyStorage: legacyOk,
      externalAppDir: ext?.path,
    );
  }
  return resolvePlatformDownloadRoot(
    isDesktopPlatform: false,
    isAndroidPlatform: false,
    isIosPlatform: isMobile,
  );
}

/// Directory for partial download files on the same storage volume as the
/// destination so finishing is a rename, not a copy (docs/DOWNLOADS.md §5.6).
Future<String?> platformPartialDir(DownloadRoot root) async {
  if (isDesktop) {
    return p.join(root.directory, '.partial');
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

/// Moves finished Phase 6 downloads from [legacyRoot] into [targetRoot]
/// (`Movies/Cinemakom`, docs/DOWNLOADS.md §5.6). Same-volume rename; if a
/// move fails the row keeps its existing path so nothing breaks.
Future<int> migrateLegacyDownloads({
  required DownloadStore store,
  required String legacyRoot,
  required String targetRoot,
  required Future<String> Function(Download) pathOf,
  Future<void> Function(String path)? onMoved,
}) async {
  final normLegacy = p.normalize(legacyRoot).toLowerCase();
  final normTarget = p.normalize(targetRoot).toLowerCase();
  if (normLegacy == normTarget) return 0;

  var movedCount = 0;
  for (final d in await store.all()) {
    if (d.status != DownloadStatus.complete) continue;
    final oldPath = await pathOf(d);
    final normOld = p.normalize(oldPath).toLowerCase();
    if (!normOld.startsWith('$normLegacy${p.separator}')) continue;
    final oldFile = File(oldPath);
    if (!oldFile.existsSync()) continue;

    final relFolder = p.basename(p.dirname(oldPath));
    final newDir = p.join(targetRoot, relFolder);
    try {
      await Directory(newDir).create(recursive: true);
      final ext = p.extension(d.fileName);
      final baseStem = p.basenameWithoutExtension(d.fileName);
      final uniqueStem = uniqueFileStem(newDir, baseStem, ext: ext);
      final newFileName = '$uniqueStem$ext';
      final newVideoPath = p.join(newDir, newFileName);

      await _moveFile(oldFile, newVideoPath);

      final oldDir = p.dirname(oldPath);
      final newSubs = <DownloadedSubtitle>[];
      for (final s in d.subtitles) {
        final oldSub = File(p.join(oldDir, s.fileName));
        if (!oldSub.existsSync()) continue;
        final suffix = s.fileName.startsWith(baseStem)
            ? s.fileName.substring(baseStem.length)
            : '.${s.language}.${s.format}';
        final newSubName = '$uniqueStem$suffix';
        try {
          await _moveFile(oldSub, p.join(newDir, newSubName));
          newSubs.add(
            DownloadedSubtitle(
              language: s.language,
              fileName: newSubName,
              format: s.format,
            ),
          );
        } on FileSystemException {
          // Keep video moved even if a subtitle couldn't move.
        }
      }

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
      debugPrint('[downloads] migrated ${d.videoId} -> $newVideoPath');

      // Remove empty legacy title folder.
      try {
        final dir = Directory(oldDir);
        if (dir.existsSync() && dir.listSync(followLinks: false).isEmpty) {
          dir.deleteSync();
        }
      } on FileSystemException {
        // Ignore.
      }
    } on FileSystemException catch (e) {
      debugPrint('[downloads] migration skipped for ${d.videoId}: $e');
    }
  }
  return movedCount;
}

Future<void> _moveFile(File src, String destPath) async {
  try {
    await src.rename(destPath);
  } on FileSystemException {
    await src.copy(destPath);
    await src.delete();
  }
}

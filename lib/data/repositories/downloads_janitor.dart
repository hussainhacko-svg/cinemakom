import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import '../models/download.dart';

/// What [DownloadsJanitor.sweep] removed.
class JanitorReport {
  const JanitorReport({
    this.removedTempFiles = 0,
    this.removedVideos = 0,
    this.removedSubtitles = 0,
    this.removedDirs = 0,
    this.reclaimedBytes = 0,
  });

  final int removedTempFiles;
  final int removedVideos;
  final int removedSubtitles;
  final int removedDirs;
  final int reclaimedBytes;

  int get totalRemoved =>
      removedTempFiles + removedVideos + removedSubtitles + removedDirs;

  @override
  String toString() =>
      'JanitorReport(temp=$removedTempFiles, videos=$removedVideos, '
      'subs=$removedSubtitles, dirs=$removedDirs, bytes=$reclaimedBytes)';
}

/// Sweeps stray files left behind by the download engine (docs/DOWNLOADS.md
/// §5.7):
/// 1. Stray `com.bbflight.background_downloader*` temp files in every engine
///    temp folder.
/// 2. Half-written or orphaned video files in download folders.
/// 3. Orphan subtitles and empty folders.
///
/// Pure file-system logic so it can be unit-tested on a real temp directory.
class DownloadsJanitor {
  const DownloadsJanitor({
    this.activeTempWindow = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const tempFilePrefix = 'com.bbflight.background_downloader';
  static const _videoExts = {'.mp4', '.mkv', '.webm', '.mov', '.m4v'};
  static const _subtitleExts = {'.srt', '.vtt', '.ass'};

  /// A temp file written within this window is treated as belonging to a
  /// currently running download.
  final Duration activeTempWindow;
  final DateTime Function() _clock;

  /// Total bytes of all `com.bbflight.background_downloader*` temp files in
  /// [tempDirs] (for the Downloads screen storage line, §5.7).
  Future<int> tempBytes(Iterable<String> tempDirs) async {
    var total = 0;
    for (final dirPath in tempDirs.toSet()) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is! File) continue;
          if (!p.basename(entity.path).startsWith(tempFilePrefix)) continue;
          try {
            total += entity.lengthSync();
          } on FileSystemException {
            // File disappeared while measuring.
          }
        }
      } on FileSystemException {
        // Folder unreadable.
      }
    }
    return total;
  }

  /// Removes stray temp files, half-written videos, orphan subtitles and empty
  /// directories. Logs a single `[downloads]` line when anything is removed.
  Future<JanitorReport> sweep({
    required List<Download> rows,
    required Iterable<String> tempDirs,
    required Iterable<String> downloadRoots,
    required Future<String> Function(Download) pathOf,
    required Future<bool> Function(String videoId) canResume,
  }) async {
    var removedTemp = 0;
    var removedVideos = 0;
    var removedSubs = 0;
    var removedDirs = 0;
    var reclaimed = 0;

    // 1. Stray temp files.
    final tempResult = await _sweepTempFiles(
      rows: rows,
      tempDirs: tempDirs,
      canResume: canResume,
    );
    removedTemp += tempResult.$1;
    reclaimed += tempResult.$2;

    // Build expected paths from rows.
    final completeVideos = <String, int?>{};
    final rowVideoPaths = <String, String>{};
    for (final d in rows) {
      final videoPath = _norm(await pathOf(d));
      rowVideoPaths[d.videoId] = videoPath;
      if (d.status == DownloadStatus.complete) {
        completeVideos[videoPath] = d.totalBytes;
      }
    }

    final normalizedTempDirs = {for (final t in tempDirs) _norm(t)};

    // 2. Half-written / orphaned videos and 3. Orphan subtitles + empty dirs.
    for (final rootPath in downloadRoots.toSet()) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      final normRoot = _norm(rootPath);

      final allFiles = <File>[];
      final subDirs = <Directory>[];
      try {
        for (final entity in root.listSync(
          recursive: true,
          followLinks: false,
        )) {
          final norm = _norm(entity.path);
          if (_isUnderAny(norm, normalizedTempDirs) ||
              p.basename(entity.path) == '.partial' ||
              p.split(entity.path).contains('.partial')) {
            continue;
          }
          if (entity is File) {
            allFiles.add(entity);
          } else if (entity is Directory) {
            subDirs.add(entity);
          }
        }
      } on FileSystemException {
        continue;
      }

      // 2a. Videos.
      final survivingVideos = <String>{};
      for (final file in allFiles) {
        final ext = p.extension(file.path).toLowerCase();
        if (!_videoExts.contains(ext)) continue;
        final norm = _norm(file.path);
        final knownComplete = completeVideos.containsKey(norm);
        final expectedSize = completeVideos[norm];
        int actualSize;
        try {
          actualSize = file.lengthSync();
        } on FileSystemException {
          continue;
        }
        final halfWritten =
            knownComplete &&
            expectedSize != null &&
            expectedSize > 0 &&
            actualSize != expectedSize;
        if (!knownComplete || halfWritten) {
          if (_deleteFileSync(file)) {
            removedVideos++;
            reclaimed += actualSize;
          }
        } else {
          survivingVideos.add(norm);
        }
      }

      // 3a. Orphan subtitles (not owned by any active row or surviving complete
      // video).
      final validSubtitles = <String>{};
      for (final d in rows) {
        final videoPath = rowVideoPaths[d.videoId]!;
        final dir = p.dirname(videoPath);
        final keep = d.status.isActive || survivingVideos.contains(videoPath);
        if (!keep) continue;
        for (final s in d.subtitles) {
          validSubtitles.add(_norm(p.join(dir, s.fileName)));
        }
      }

      for (final file in allFiles) {
        final ext = p.extension(file.path).toLowerCase();
        if (!_subtitleExts.contains(ext)) continue;
        final norm = _norm(file.path);
        if (!validSubtitles.contains(norm)) {
          final size = _safeLengthSync(file);
          if (_deleteFileSync(file)) {
            removedSubs++;
            reclaimed += size;
          }
        }
      }

      // 3b. Empty folders (deepest first; never delete the download root).
      subDirs.sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final dir in subDirs) {
        if (_norm(dir.path) == normRoot) continue;
        try {
          if (dir.listSync(followLinks: false).isEmpty) {
            dir.deleteSync();
            removedDirs++;
          }
        } on FileSystemException {
          // Not empty or already gone.
        }
      }
    }

    final report = JanitorReport(
      removedTempFiles: removedTemp,
      removedVideos: removedVideos,
      removedSubtitles: removedSubs,
      removedDirs: removedDirs,
      reclaimedBytes: reclaimed,
    );
    if (report.totalRemoved > 0) {
      debugPrint(
        '[downloads] janitor removed temp=$removedTemp videos=$removedVideos '
        'subs=$removedSubs dirs=$removedDirs reclaimed=$reclaimed bytes',
      );
    }
    return report;
  }

  Future<(int, int)> _sweepTempFiles({
    required List<Download> rows,
    required Iterable<String> tempDirs,
    required Future<bool> Function(String videoId) canResume,
  }) async {
    final activeRows = rows.where((d) => d.status.isActive).toList();
    final runningCount = activeRows
        .where((d) => d.status == DownloadStatus.running)
        .length;
    var resumableOtherCount = 0;
    for (final d in activeRows) {
      if (d.status == DownloadStatus.running) continue;
      if (await canResume(d.videoId)) {
        resumableOtherCount++;
      }
    }

    final entries = <({File file, DateTime modified, int size})>[];
    for (final dirPath in tempDirs.toSet()) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is! File) continue;
          if (!p.basename(entity.path).startsWith(tempFilePrefix)) continue;
          try {
            final stat = entity.statSync();
            entries.add((
              file: entity,
              modified: stat.modified,
              size: stat.size,
            ));
          } on FileSystemException {
            // File disappeared while listing.
          }
        }
      } on FileSystemException {
        // Folder unreadable.
      }
    }

    if (entries.isEmpty) return (0, 0);

    // Newest first.
    entries.sort((a, b) => b.modified.compareTo(a.modified));

    final keep = <String>{};
    if (runningCount > 0 || resumableOtherCount > 0) {
      final now = _clock();
      var runningLeft = runningCount;
      var resumableLeft = resumableOtherCount;
      for (final e in entries) {
        final age = now.difference(e.modified);
        if (runningLeft > 0 && age <= activeTempWindow) {
          keep.add(_norm(e.file.path));
          runningLeft--;
        } else if (resumableLeft > 0) {
          keep.add(_norm(e.file.path));
          resumableLeft--;
        }
      }
    }

    var removed = 0;
    var reclaimed = 0;
    for (final e in entries) {
      if (keep.contains(_norm(e.file.path))) continue;
      if (_deleteFileSync(e.file)) {
        removed++;
        reclaimed += e.size;
      }
    }
    return (removed, reclaimed);
  }

  static String _norm(String path) => p.normalize(path).toLowerCase();

  static bool _isUnderAny(String path, Set<String> roots) =>
      roots.any((r) => path == r || path.startsWith('$r${p.separator}'));

  static int _safeLengthSync(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  static bool _deleteFileSync(File file) {
    try {
      file.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

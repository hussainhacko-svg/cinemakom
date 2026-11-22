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
/// 2. The leftover video of a *failed* download, at that download's own path
///    (an interrupted copy). Nothing else: the download folders are the
///    user's (`Movies/Cinemakom`, `~/Videos/Cinemakom`), so a video or
///    subtitle no row claims (renamed, from an earlier install, put there by
///    hand) and a finished download's video are never deleted (PR #4 review,
///    critical 1, 2026-11-22).
/// 3. The subtitles of a failed row whose video is gone, and empty folders.
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
  ///
  /// [privateRoots] are app-private download folders (the Phase 6
  /// `Android/data/<pkg>/files/Downloads`): the user can't see or manage
  /// them, so there a video or subtitle no row claims is removed too.
  /// [exclude] lists rows whose temp file was just discarded (a restart), so
  /// they don't keep a temp-file slot.
  Future<JanitorReport> sweep({
    required List<Download> rows,
    required Iterable<String> tempDirs,
    required Iterable<String> downloadRoots,
    required Future<String> Function(Download) pathOf,
    required Future<bool> Function(String videoId) canResume,
    Iterable<String> privateRoots = const [],
    Set<String> exclude = const {},
    Map<String, String> protectedTemp = const {},
  }) async {
    var removedTemp = 0;
    var removedVideos = 0;
    var removedSubs = 0;
    var removedDirs = 0;
    var reclaimed = 0;

    // 1. Stray temp files.
    final tempResult = await _sweepTempFiles(
      rows: [
        for (final d in rows)
          if (!exclude.contains(d.videoId)) d,
      ],
      tempDirs: tempDirs,
      canResume: canResume,
      protectedTemp: {
        for (final e in protectedTemp.entries)
          if (!exclude.contains(e.key)) e.key: e.value,
      },
    );
    removedTemp += tempResult.$1;
    reclaimed += tempResult.$2;

    // The paths rows own. Only a failed row's leftover video may go; a
    // complete, queued, running or paused row's file is kept (a queued or
    // running one may have just been moved into place natively, moments
    // before its `complete` event reaches Dart).
    final failedVideos = <String>{};
    final keptRowVideos = <String>{};
    final rowVideoPaths = <String, String>{};
    final claimedSubtitles = <String>{};
    for (final d in rows) {
      final videoPath = _norm(await pathOf(d));
      rowVideoPaths[d.videoId] = videoPath;
      if (d.status == DownloadStatus.failed) {
        failedVideos.add(videoPath);
      } else {
        keptRowVideos.add(videoPath);
      }
      for (final s in d.subtitles) {
        claimedSubtitles.add(_norm(p.join(p.dirname(videoPath), s.fileName)));
      }
    }
    // Two rows can share a path (a failed attempt, then a new one): keep it.
    failedVideos.removeAll(keptRowVideos);

    final normalizedTempDirs = {for (final t in tempDirs) _norm(t)};
    final private = {for (final r in privateRoots) _norm(r)};

    // 2. Half-written / orphaned videos and 3. Orphan subtitles + empty dirs.
    for (final rootPath in {...downloadRoots, ...privateRoots}) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      final normRoot = _norm(rootPath);
      final isPrivate = private.contains(normRoot);

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

      // 2a. Videos: only a failed row's leftover.
      final survivingVideos = <String>{};
      for (final file in allFiles) {
        final ext = p.extension(file.path).toLowerCase();
        if (!_videoExts.contains(ext)) continue;
        final norm = _norm(file.path);
        final orphanInPrivate = isPrivate && !keptRowVideos.contains(norm);
        if (!failedVideos.contains(norm) && !orphanInPrivate) {
          survivingVideos.add(norm);
          continue;
        }
        final size = _safeLengthSync(file);
        if (_deleteFileSync(file)) {
          removedVideos++;
          reclaimed += size;
        }
      }

      // 3a. The subtitles of a failed row whose video is gone. A finished
      // row's stay even if its video was renamed (they go with it), and a
      // subtitle no row lists is the user's: kept.
      final keptSubtitles = <String>{};
      final droppedSubtitles = <String>{};
      for (final d in rows) {
        final videoPath = rowVideoPaths[d.videoId]!;
        final dir = p.dirname(videoPath);
        final keep =
            d.status != DownloadStatus.failed ||
            survivingVideos.contains(videoPath);
        for (final s in d.subtitles) {
          (keep ? keptSubtitles : droppedSubtitles).add(
            _norm(p.join(dir, s.fileName)),
          );
        }
      }
      droppedSubtitles.removeAll(keptSubtitles);

      for (final file in allFiles) {
        final ext = p.extension(file.path).toLowerCase();
        if (!_subtitleExts.contains(ext)) continue;
        final norm = _norm(file.path);
        final orphanInPrivate = isPrivate && !claimedSubtitles.contains(norm);
        if (droppedSubtitles.contains(norm) || orphanInPrivate) {
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
    required Map<String, String> protectedTemp,
  }) async {
    // Files the engine's resume data names exactly are kept, and their rows
    // need no slot below.
    final protectedPaths = {
      for (final path in protectedTemp.values) _norm(path),
    };
    // Each unfinished download owns at most one temp file (rule 1). Running
    // and queued rows each keep a slot: a queued row may be waiting to
    // retry from its partial file (up to 512 s between tries), or be the
    // holding queue's next task, started natively moments before Dart
    // hears of it (PR #4 review, critical 2). A paused or failed row keeps
    // one only while the engine can still resume it.
    var slots = 0;
    for (final d in rows) {
      if (protectedTemp.containsKey(d.videoId)) continue;
      switch (d.status) {
        case DownloadStatus.running || DownloadStatus.queued:
          slots++;
        case DownloadStatus.paused || DownloadStatus.failed:
          // Never asked of queued tasks: background_downloader's
          // `taskCanResume` blocks until a task starts.
          if (await canResume(d.videoId)) slots++;
        case DownloadStatus.complete:
          break;
      }
    }
    // Only a running or queued download writes to a temp file.
    final anyLive = rows.any(
      (d) =>
          d.status == DownloadStatus.running ||
          d.status == DownloadStatus.queued,
    );

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

    entries.removeWhere((e) => protectedPaths.contains(_norm(e.file.path)));
    if (entries.isEmpty) return (0, 0);

    // Newest first: the engine writes to the live ones. Which file is whose
    // isn't known (§5.7), so the newest [slots] stay, and so does any file
    // written in the last [activeTempWindow] while a download runs or waits.
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    final now = _clock();
    final keep = <String>{};
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final recent = now.difference(e.modified) <= activeTempWindow;
      if (i < slots || (anyLive && recent)) keep.add(_norm(e.file.path));
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

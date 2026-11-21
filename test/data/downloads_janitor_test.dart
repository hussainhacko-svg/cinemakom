import 'dart:io';

import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/repositories/downloads_janitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Download _row(
  String id, {
  required String dir,
  required String fileName,
  DownloadStatus status = DownloadStatus.complete,
  int? totalBytes,
  List<DownloadedSubtitle> subtitles = const [],
}) => Download(
  videoId: id,
  titleId: id,
  title: LocalizedText(en: id),
  quality: '1080p',
  baseDirectory: 'root',
  directory: dir,
  fileName: fileName,
  status: status,
  totalBytes: totalBytes,
  subtitles: subtitles,
  addedAt: DateTime(2026, 11, 21),
);

File _write(String path, int bytes, {DateTime? modified}) {
  final f = File(path)..createSync(recursive: true);
  f.writeAsBytesSync(List.filled(bytes, 7));
  if (modified != null) f.setLastModifiedSync(modified);
  return f;
}

void main() {
  late Directory root;
  late Directory tempDir;
  late Directory dlRoot;
  final now = DateTime(2026, 11, 21, 12, 0);

  setUp(() {
    root = Directory.systemTemp.createTempSync('janitor-test');
    tempDir = Directory(p.join(root.path, 'engine_temp'))..createSync();
    dlRoot = Directory(p.join(root.path, 'Downloads'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'removes all stray temp files when there are no unfinished tasks',
    () async {
      final stray1 = _write(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}111'),
        500,
        modified: now.subtract(const Duration(seconds: 10)),
      );
      final stray2 = _write(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}222'),
        700,
        modified: now.subtract(const Duration(hours: 2)),
      );
      final unrelated = _write(p.join(tempDir.path, 'other.db'), 100);

      final janitor = DownloadsJanitor(clock: () => now);
      expect(await janitor.tempBytes([tempDir.path]), 1200);

      final report = await janitor.sweep(
        rows: const [],
        tempDirs: [tempDir.path],
        downloadRoots: [dlRoot.path],
        pathOf: (d) async => p.join(d.directory, d.fileName),
        canResume: (_) async => false,
      );

      expect(report.removedTempFiles, 2);
      expect(report.reclaimedBytes, 1200);
      expect(stray1.existsSync(), isFalse);
      expect(stray2.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
      expect(await janitor.tempBytes([tempDir.path]), 0);
    },
  );

  test(
    'keeps running (recent) and resumable paused temp files, deletes strays',
    () async {
      final runningTemp = _write(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}run'),
        1000,
        modified: now.subtract(const Duration(seconds: 30)),
      );
      final pausedTemp = _write(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}paused'),
        2000,
        modified: now.subtract(const Duration(hours: 1)),
      );
      final oldStray = _write(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}stray'),
        3000,
        modified: now.subtract(const Duration(days: 1)),
      );

      final rows = [
        _row(
          'r1',
          dir: dlRoot.path,
          fileName: 'r1.mp4',
          status: DownloadStatus.running,
        ),
        _row(
          'p1',
          dir: dlRoot.path,
          fileName: 'p1.mp4',
          status: DownloadStatus.paused,
        ),
        _row(
          'f1',
          dir: dlRoot.path,
          fileName: 'f1.mp4',
          status: DownloadStatus.failed,
        ),
      ];

      final janitor = DownloadsJanitor(clock: () => now);
      final report = await janitor.sweep(
        rows: rows,
        tempDirs: [tempDir.path],
        downloadRoots: [dlRoot.path],
        pathOf: (d) async => p.join(d.directory, d.fileName),
        // Only p1 is resumable; f1 is not.
        canResume: (id) async => id == 'p1',
      );

      expect(report.removedTempFiles, 1);
      expect(report.reclaimedBytes, 3000);
      expect(runningTemp.existsSync(), isTrue);
      expect(pausedTemp.existsSync(), isTrue);
      expect(oldStray.existsSync(), isFalse);
    },
  );

  test('keeps every video the user owns; removes only a failed download\'s '
      'leftover, its subtitles and empty folders', () async {
    final goodDir = p.join(dlRoot.path, 'Good Movie');
    final goodVideo = _write(p.join(goodDir, 'Good Movie 1080p.mp4'), 1000);
    final goodSub = _write(p.join(goodDir, 'Good Movie 1080p.ar.srt'), 50);

    // A finished download whose size doesn't match: still the user's.
    final halfDir = p.join(dlRoot.path, 'Half Movie');
    final halfVideo = _write(p.join(halfDir, 'Half Movie 1080p.mp4'), 400);
    final halfSub = _write(p.join(halfDir, 'Half Movie 1080p.en.srt'), 40);

    // A finished download the user renamed: the row's path is gone.
    final renamedDir = p.join(dlRoot.path, 'Renamed Movie');
    final renamedVideo = _write(p.join(renamedDir, 'My copy.mp4'), 900);
    final renamedSub = _write(
      p.join(renamedDir, 'Renamed Movie 1080p.ar.srt'),
      45,
    );

    final activeDir = p.join(dlRoot.path, 'Active Movie');
    final activeSub = _write(p.join(activeDir, 'Active Movie 720p.ar.srt'), 30);

    // No row at all: an earlier install's download, or the user's own.
    final strayDir = p.join(dlRoot.path, 'Orphan');
    final strayVideo = _write(p.join(strayDir, 'stray.mp4'), 250);
    final straySub = _write(p.join(strayDir, 'stray.srt'), 20);

    // A failed download's interrupted copy at its own path.
    final brokenDir = p.join(dlRoot.path, 'Broken Movie');
    final brokenVideo = _write(p.join(brokenDir, 'Broken Movie 720p.mp4'), 300);
    final brokenSub = _write(p.join(brokenDir, 'Broken Movie 720p.ar.srt'), 25);

    final emptyDir = Directory(p.join(dlRoot.path, 'Empty'))..createSync();

    const arSub = DownloadedSubtitle(
      language: 'ar',
      fileName: 'Good Movie 1080p.ar.srt',
      format: 'srt',
    );
    final rows = [
      _row(
        'good',
        dir: goodDir,
        fileName: 'Good Movie 1080p.mp4',
        totalBytes: 1000,
        subtitles: const [arSub],
      ),
      _row(
        'half',
        dir: halfDir,
        fileName: 'Half Movie 1080p.mp4',
        totalBytes: 2000, // mismatch: only 400 bytes on disk
        subtitles: const [
          DownloadedSubtitle(
            language: 'en',
            fileName: 'Half Movie 1080p.en.srt',
            format: 'srt',
          ),
        ],
      ),
      _row(
        'renamed',
        dir: renamedDir,
        fileName: 'Renamed Movie 1080p.mp4',
        totalBytes: 900,
        subtitles: const [
          DownloadedSubtitle(
            language: 'ar',
            fileName: 'Renamed Movie 1080p.ar.srt',
            format: 'srt',
          ),
        ],
      ),
      _row(
        'active',
        dir: activeDir,
        fileName: 'Active Movie 720p.mp4',
        status: DownloadStatus.running,
        subtitles: const [
          DownloadedSubtitle(
            language: 'ar',
            fileName: 'Active Movie 720p.ar.srt',
            format: 'srt',
          ),
        ],
      ),
      _row(
        'broken',
        dir: brokenDir,
        fileName: 'Broken Movie 720p.mp4',
        status: DownloadStatus.failed,
        subtitles: const [
          DownloadedSubtitle(
            language: 'ar',
            fileName: 'Broken Movie 720p.ar.srt',
            format: 'srt',
          ),
        ],
      ),
    ];

    final janitor = DownloadsJanitor(clock: () => now);
    final report = await janitor.sweep(
      rows: rows,
      tempDirs: [tempDir.path],
      downloadRoots: [dlRoot.path],
      pathOf: (d) async => p.join(d.directory, d.fileName),
      canResume: (_) async => false,
    );

    for (final kept in [
      goodVideo,
      goodSub,
      halfVideo,
      halfSub,
      renamedVideo,
      renamedSub,
      activeSub,
      strayVideo,
      straySub,
    ]) {
      expect(kept.existsSync(), isTrue, reason: kept.path);
    }

    expect(brokenVideo.existsSync(), isFalse);
    expect(brokenSub.existsSync(), isFalse);
    expect(Directory(brokenDir).existsSync(), isFalse);
    expect(emptyDir.existsSync(), isFalse);
    expect(dlRoot.existsSync(), isTrue);

    expect(report.removedVideos, 1);
    expect(report.removedSubtitles, 1);
    expect(report.removedDirs, 2);
    expect(report.reclaimedBytes, 300 + 25);
  });

  test('after the app\'s data is cleared (no rows), nothing in the download '
      'folder is deleted', () async {
    final video = _write(
      p.join(dlRoot.path, 'Old', 'Old Movie 1080p.mp4'),
      800,
    );
    final sub = _write(
      p.join(dlRoot.path, 'Old', 'Old Movie 1080p.ar.srt'),
      30,
    );
    final report = await DownloadsJanitor(clock: () => now).sweep(
      rows: const [],
      tempDirs: [tempDir.path],
      downloadRoots: [dlRoot.path],
      pathOf: (d) async => p.join(d.directory, d.fileName),
      canResume: (_) async => false,
    );
    expect(video.existsSync(), isTrue);
    expect(sub.existsSync(), isTrue);
    expect(report.removedVideos, 0);
    expect(report.removedSubtitles, 0);
  });

  test('never queries canResume on queued/running tasks and never deletes in-progress videos', () async {
    final queried = <String>[];
    final ep2Video = _write(p.join(dlRoot.path, 'Show', 'ep2.mp4'), 2048);
    final rows = [
      _row(
        'q1',
        dir: p.join(dlRoot.path, 'Show'),
        fileName: 'q1.mp4',
        status: DownloadStatus.queued,
      ),
      _row(
        'ep2',
        dir: p.join(dlRoot.path, 'Show'),
        fileName: 'ep2.mp4',
        status: DownloadStatus.running,
      ),
      _row(
        'p1',
        dir: p.join(dlRoot.path, 'Show'),
        fileName: 'p1.mp4',
        status: DownloadStatus.paused,
      ),
    ];
    final janitor = DownloadsJanitor(clock: () => now);
    final report = await janitor.sweep(
      rows: rows,
      tempDirs: [tempDir.path],
      downloadRoots: [dlRoot.path],
      pathOf: (d) async => p.join(d.directory, d.fileName),
      canResume: (id) async {
        queried.add(id);
        return true;
      },
    );
    expect(queried, ['p1']);
    expect(ep2Video.existsSync(), isTrue);
    expect(report.removedVideos, 0);
  });
}

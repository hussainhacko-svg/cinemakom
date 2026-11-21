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

  test(
    'deletes half-written videos, orphan subtitles and empty folders',
    () async {
      final goodDir = p.join(dlRoot.path, 'Good Movie');
      final goodVideo = _write(p.join(goodDir, 'Good Movie 1080p.mp4'), 1000);
      final goodSub = _write(p.join(goodDir, 'Good Movie 1080p.ar.srt'), 50);

      final halfDir = p.join(dlRoot.path, 'Half Movie');
      final halfVideo = _write(p.join(halfDir, 'Half Movie 1080p.mp4'), 400);
      final halfSub = _write(p.join(halfDir, 'Half Movie 1080p.en.srt'), 40);

      final activeDir = p.join(dlRoot.path, 'Active Movie');
      final activeSub = _write(
        p.join(activeDir, 'Active Movie 720p.ar.srt'),
        30,
      );

      final strayDir = p.join(dlRoot.path, 'Orphan');
      final strayVideo = _write(p.join(strayDir, 'stray.mp4'), 250);
      final straySub = _write(p.join(strayDir, 'stray.srt'), 20);

      final emptyDir = Directory(p.join(dlRoot.path, 'Empty'))..createSync();

      final rows = [
        _row(
          'good',
          dir: goodDir,
          fileName: 'Good Movie 1080p.mp4',
          status: DownloadStatus.complete,
          totalBytes: 1000,
          subtitles: const [
            DownloadedSubtitle(
              language: 'ar',
              fileName: 'Good Movie 1080p.ar.srt',
              format: 'srt',
            ),
          ],
        ),
        _row(
          'half',
          dir: halfDir,
          fileName: 'Half Movie 1080p.mp4',
          status: DownloadStatus.complete,
          totalBytes: 2000, // mismatch: only 400 bytes written
          subtitles: const [
            DownloadedSubtitle(
              language: 'en',
              fileName: 'Half Movie 1080p.en.srt',
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
      ];

      final janitor = DownloadsJanitor(clock: () => now);
      final report = await janitor.sweep(
        rows: rows,
        tempDirs: [tempDir.path],
        downloadRoots: [dlRoot.path],
        pathOf: (d) async => p.join(d.directory, d.fileName),
        canResume: (_) async => false,
      );

      expect(goodVideo.existsSync(), isTrue);
      expect(goodSub.existsSync(), isTrue);
      expect(activeSub.existsSync(), isTrue);

      expect(halfVideo.existsSync(), isFalse);
      expect(halfSub.existsSync(), isFalse);
      expect(strayVideo.existsSync(), isFalse);
      expect(straySub.existsSync(), isFalse);
      expect(Directory(halfDir).existsSync(), isFalse);
      expect(Directory(strayDir).existsSync(), isFalse);
      expect(emptyDir.existsSync(), isFalse);
      expect(dlRoot.existsSync(), isTrue);

      expect(report.removedVideos, 2);
      expect(report.removedSubtitles, 2);
      expect(report.removedDirs, 3);
      expect(report.reclaimedBytes, 400 + 40 + 250 + 20);
    },
  );
}

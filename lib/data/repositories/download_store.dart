import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/network/api_endpoints.dart' show VideoKind;
import '../../core/storage/database.dart';
import '../models/download.dart';
import '../models/localized_text.dart';

/// The `downloads` table. The downloads service is the only writer.
abstract interface class DownloadStore {
  /// Every download, the newest first.
  Stream<List<Download>> watchAll();

  Future<List<Download>> all();

  Future<Download?> get(String videoId);

  /// Saves or replaces the row for [download.videoId].
  Future<void> put(Download download);

  Future<void> remove(String videoId);
}

class DriftDownloadStore implements DownloadStore {
  DriftDownloadStore(this._db);

  final AppDatabase _db;

  static Download _fromRow(DownloadRow r) => Download(
    videoId: r.videoId,
    titleId: r.titleId,
    title: LocalizedText(en: r.titleEn, ar: r.titleAr),
    season: r.season,
    episode: r.episode,
    episodeLast: r.episodeLast,
    finale: r.finale,
    posterUrl: r.posterUrl,
    kind: VideoKind.values.asNameMap()[r.kind],
    year: r.year,
    duration: r.durationMs == null
        ? null
        : Duration(milliseconds: r.durationMs!),
    quality: r.quality,
    baseDirectory: r.baseDirectory,
    directory: r.directory,
    fileName: r.fileName,
    subtitles: _subtitles(r.subtitles),
    totalBytes: r.totalBytes,
    downloadedBytes: r.downloadedBytes,
    status:
        DownloadStatus.values.asNameMap()[r.status] ?? DownloadStatus.failed,
    pausedByUser: r.pausedByUser,
    startedOver: r.startedOver,
    problem: DownloadProblem.values.asNameMap()[r.problem],
    problemDetail: r.problemDetail,
    addedAt: r.addedAt,
    updatedAt: r.updatedAt,
    completedAt: r.completedAt,
    contentUri: r.contentUri,
  );

  static List<DownloadedSubtitle> _subtitles(String json) {
    try {
      final list = jsonDecode(json);
      if (list is! List) return const [];
      return [for (final s in list) ?DownloadedSubtitle.fromJson(s)];
    } on FormatException {
      return const [];
    }
  }

  SimpleSelectStatement<$DownloadsTable, DownloadRow> get _newestFirst =>
      _db.select(_db.downloads)..orderBy([
        (t) => OrderingTerm.desc(t.addedAt),
        (t) => OrderingTerm.asc(t.season),
        (t) => OrderingTerm.asc(t.episode),
      ]);

  @override
  Stream<List<Download>> watchAll() =>
      _newestFirst.watch().map((rows) => rows.map(_fromRow).toList());

  @override
  Future<List<Download>> all() async =>
      (await _newestFirst.get()).map(_fromRow).toList();

  @override
  Future<Download?> get(String videoId) async {
    final row = await (_db.select(
      _db.downloads,
    )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> put(Download d) => _db
      .into(_db.downloads)
      .insertOnConflictUpdate(
        DownloadsCompanion.insert(
          videoId: d.videoId,
          titleId: d.titleId,
          season: Value(d.season),
          episode: Value(d.episode),
          episodeLast: Value(d.episodeLast),
          finale: Value(d.finale),
          titleEn: Value(d.title.en),
          titleAr: Value(d.title.ar),
          posterUrl: Value(d.posterUrl),
          kind: Value(d.kind?.name),
          year: Value(d.year),
          durationMs: Value(d.duration?.inMilliseconds),
          quality: d.quality,
          baseDirectory: d.baseDirectory,
          directory: d.directory,
          fileName: d.fileName,
          subtitles: Value(
            jsonEncode([for (final s in d.subtitles) s.toJson()]),
          ),
          totalBytes: Value(d.totalBytes),
          downloadedBytes: Value(d.downloadedBytes),
          status: d.status.name,
          pausedByUser: Value(d.pausedByUser),
          startedOver: Value(d.startedOver),
          problem: Value(d.problem?.name),
          problemDetail: Value(d.problemDetail),
          addedAt: d.addedAt,
          updatedAt: Value(d.updatedAt),
          completedAt: Value(d.completedAt),
          contentUri: Value(d.contentUri),
        ),
      );

  @override
  Future<void> remove(String videoId) =>
      (_db.delete(_db.downloads)..where((t) => t.videoId.equals(videoId))).go();
}

/// In-memory [DownloadStore] for tests (drift's timers don't mix with
/// widget tests).
class MemoryDownloadStore implements DownloadStore {
  MemoryDownloadStore([Iterable<Download> rows = const []])
    : rows = {for (final r in rows) r.videoId: r};

  final Map<String, Download> rows;
  final _changes = StreamController<void>.broadcast();

  List<Download> get _sorted => rows.values.toList()
    ..sort((a, b) {
      final byAdded = b.addedAt.compareTo(a.addedAt);
      if (byAdded != 0) return byAdded;
      final bySeason = (a.season ?? 0).compareTo(b.season ?? 0);
      return bySeason != 0
          ? bySeason
          : (a.episode ?? 0).compareTo(b.episode ?? 0);
    });

  @override
  Stream<List<Download>> watchAll() async* {
    yield _sorted;
    await for (final _ in _changes.stream) {
      yield _sorted;
    }
  }

  @override
  Future<List<Download>> all() async => _sorted;

  @override
  Future<Download?> get(String videoId) async => rows[videoId];

  @override
  Future<void> put(Download download) async {
    rows[download.videoId] = download;
    _changes.add(null);
  }

  @override
  Future<void> remove(String videoId) async {
    rows.remove(videoId);
    _changes.add(null);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/downloads/background_file_downloader.dart';
import '../../core/downloads/downloader.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_providers.dart';
import '../../core/platform/platform_info.dart';
import '../../core/storage/preferences.dart';
import '../../features/player/quality.dart';
import '../models/download.dart';
import '../models/media_item.dart';
import '../models/playback_models.dart';
import 'download_store.dart';
import 'library_repository.dart';
import 'media_repository.dart';

/// A stream a title can be downloaded in, with its size when known.
class DownloadChoice {
  const DownloadChoice(this.source, this.bytes);

  final VideoSource source;
  final int? bytes;
}

/// A downloaded file, ready to play offline.
class LocalPlayback {
  const LocalPlayback({
    required this.path,
    required this.quality,
    required this.subtitles,
  });

  final String path;
  final String quality;

  /// Absolute paths, with their language and format.
  final List<SubtitleTrack> subtitles;
}

/// Where new downloads go: a base directory and a folder in it.
typedef DownloadRoot = ({String baseDirectory, String directory});

/// Downloads (PLAN.md Phase 6): the video with its plain Arabic and English
/// subtitles (and the styled one where the player can draw it), progress,
/// pause, resume, delete, and offline playback.
///
/// Signed stream URLs expire, so a download is always started, resumed or
/// retried with a fresh one (`MediaRepository.streams(fresh: true)`).
class DownloadsRepository {
  DownloadsRepository({
    required this._store,
    required this._downloader,
    required this._media,
    required this._api,
    required this._root,
    this.styledSubtitles = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DownloadStore _store;
  final Downloader _downloader;
  final MediaRepository _media;
  final ApiClient _api;
  final Future<DownloadRoot> Function() _root;
  final DateTime Function() _clock;

  /// Whether styled (ASS) subtitles are saved too: the player can draw them
  /// everywhere but on Android (PLAYER.md §2, decision 7).
  final bool styledSubtitles;

  /// Engine events, the user's actions and startup all read a row and
  /// write it back, so they run one at a time: a late progress event must
  /// never turn a finished download back into a running one.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  final _progress = <String, DownloadProgress>{};
  final _progressChanges = StreamController<void>.broadcast();

  /// Tasks already retried once by themselves after a refused URL.
  final _autoRetried = <String>{};
  bool _started = false;

  Stream<List<Download>> watchAll() => _store.watchAll();

  Future<Download?> get(String videoId) => _store.get(videoId);

  /// The running downloads' progress, by video ID.
  Stream<Map<String, DownloadProgress>> watchProgress() {
    StreamSubscription<void>? changes;
    late final StreamController<Map<String, DownloadProgress>> out;
    out = StreamController(
      onListen: () {
        out.add(Map.of(_progress));
        changes = _progressChanges.stream.listen(
          (_) => out.add(Map.of(_progress)),
        );
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  void _setProgress(String id, DownloadProgress? value) {
    if (value == null) {
      if (_progress.remove(id) == null) return;
    } else {
      _progress[id] = value;
    }
    _progressChanges.add(null);
  }

  // ---------------------------------------------------------------------------
  // Start

  /// Starts the engine and catches up with what happened while the app was
  /// closed. Called once, at startup.
  Future<void> start(DownloadNotices notices) async {
    if (_started) return;
    _started = true;
    _downloader.events.listen((e) => unawaited(_serial(() => _onEvent(e))));
    try {
      final root = await _root();
      await _downloader.start(
        partialDir: isDesktop ? p.join(root.directory, '.partial') : null,
      );
      await _downloader.setNotices(notices);
      await _serial(_reconcile);
    } on Object catch (e, stack) {
      // Startup never fails because of downloads; they show as failed.
      debugPrint('Downloads failed to start: $e\n$stack');
    }
  }

  Future<void> setNotices(DownloadNotices notices) =>
      _downloader.setNotices(notices);

  Future<void> _reconcile() async {
    final known = await _downloader.known();
    for (final d in await _store.all()) {
      if (!d.status.isActive || d.status == DownloadStatus.failed) continue;
      final state = known[d.videoId];
      if (state == null) {
        // The engine lost it (app data cleared, killed mid-enqueue).
        await _store.put(
          d.copyWith(
            status: DownloadStatus.failed,
            problem: DownloadProblem.network,
          ),
        );
      } else if (state == DownloaderState.complete) {
        await _complete(d);
      } else if (state == DownloaderState.failed) {
        await _store.put(
          d.copyWith(
            status: DownloadStatus.failed,
            problem: DownloadProblem.network,
          ),
        );
      } else if (state == DownloaderState.paused) {
        await _store.put(d.copyWith(status: DownloadStatus.paused));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Choosing what to download

  /// Every quality of [videoId], highest first, with file sizes (asked of
  /// the CDN in parallel; `null` when it doesn't say).
  Future<List<DownloadChoice>> choices(String videoId) async {
    final sources = [...await _media.streams(videoId, fresh: true)]
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    final sizes = await Future.wait(
      sources.map((s) => _api.contentLength(s.url)),
    );
    return [
      for (var i = 0; i < sources.length; i++)
        DownloadChoice(sources[i], sizes[i]),
    ];
  }

  // ---------------------------------------------------------------------------
  // Downloading

  /// Downloads [item] (a movie), or its [episode], in [source]'s quality.
  /// Does nothing when it's already downloaded or on its way.
  Future<void> download(
    MediaItem item, {
    Episode? episode,
    required VideoSource source,
    int? bytes,
  }) => _serial(
    () => _download(item, episode: episode, source: source, bytes: bytes),
  );

  Future<void> _download(
    MediaItem item, {
    Episode? episode,
    required VideoSource source,
    int? bytes,
  }) async {
    final videoId = episode?.id ?? item.id;
    final existing = await _store.get(videoId);
    if (existing != null && existing.status != DownloadStatus.failed) return;

    final root = await _root();
    final title = item.title.en ?? item.title.ar ?? videoId;
    final folder = p.join(
      root.directory,
      _safe(title, fallback: item.seriesId),
    );
    final stem = _safe(
      [
        title,
        if (episode != null)
          'S${_two(episode.season)}E${_two(episode.numbering.first)}'
              '${episode.numbering.last != episode.numbering.first ? '-E${_two(episode.numbering.last)}' : ''}',
        source.label,
      ].join(' '),
      fallback: videoId,
    );
    final spot = FileSpot(root.baseDirectory, folder, '$stem.mp4');

    final subtitles = await _saveSubtitles(videoId, spot, stem);
    final download = Download(
      videoId: videoId,
      titleId: item.seriesId,
      title: item.title,
      season: episode?.season,
      episode: episode?.episode,
      episodeLast: episode == null || episode.numbering.last == episode.episode
          ? null
          : episode.numbering.last,
      finale: episode?.numbering.isFinale ?? false,
      posterUrl: item.posterUrl ?? item.hdPosterUrl,
      kind: item.kind,
      year: item.year,
      duration: episode?.duration ?? item.duration,
      quality: source.label,
      baseDirectory: spot.baseDirectory,
      directory: spot.directory,
      fileName: spot.fileName,
      subtitles: subtitles,
      totalBytes: bytes,
      status: DownloadStatus.queued,
      addedAt: _clock(),
    );
    await _store.put(download);
    await _downloader.askToNotify();
    if (!await _downloader.enqueue(_job(download, source.url))) {
      await _fail(download, DownloadProblem.unknown);
    }
  }

  /// Queues every episode in [episodes] that isn't downloaded yet, each in
  /// the quality closest to [height]. Returns how many were queued.
  Future<int> downloadEpisodes(
    MediaItem series,
    List<Episode> episodes,
    int height,
  ) async {
    var queued = 0;
    for (final e in episodes) {
      final existing = await _store.get(e.id);
      if (existing != null && existing.status != DownloadStatus.failed) {
        continue;
      }
      final List<VideoSource> sources;
      try {
        sources = await _media.streams(e.id, fresh: true);
      } on Object {
        continue;
      }
      final source = pickQuality(sources, height);
      if (source == null) continue;
      await download(series, episode: e, source: source);
      queued++;
    }
    return queued;
  }

  /// The CDN serves ranges (206, strong ETag) but sends no `Accept-Ranges`
  /// on a plain 200, so background_downloader would think a download can't
  /// be paused or resumed. Asking for the whole file as a range from the
  /// first byte gets a 206, and resume adds its offset to this range's
  /// start (docs/API.md §3, File sizes and ranges).
  static const _wholeFile = {'Range': 'bytes=0-'};

  DownloadJob _job(Download d, String url) => DownloadJob(
    taskId: d.videoId,
    url: url,
    headers: {...ApiClient.defaultHeaders, ..._wholeFile},
    spot: FileSpot(d.baseDirectory, d.directory, d.fileName),
    displayName: _displayName(d),
  );

  static String _displayName(Download d) {
    final title = d.title.en ?? d.title.ar ?? '';
    return d.isEpisode
        ? '$title · S${_two(d.season!)}E${_two(d.episode!)}'
        : title;
  }

  /// Saves the plain Arabic and English subtitles (and the styled Arabic
  /// one when [styledSubtitles]) beside the video. Failures are skipped:
  /// a download never waits on its subtitles.
  Future<List<DownloadedSubtitle>> _saveSubtitles(
    String videoId,
    FileSpot spot,
    String stem,
  ) async {
    final List<SubtitleTrack> tracks;
    try {
      tracks = oneTrackPerLanguage(await _media.subtitles(videoId));
    } on Object {
      return const [];
    }
    final wanted = [
      for (final t in tracks)
        if ((t.languageCode == 'ar' || t.languageCode == 'en') &&
            (!t.isStyled || styledSubtitles))
          t,
    ];
    if (wanted.isEmpty) return const [];
    final dir = p.dirname(await _downloader.pathOf(spot));
    await Directory(dir).create(recursive: true);
    final saved = <DownloadedSubtitle>[];
    for (final t in wanted) {
      final name =
          '$stem.${t.languageCode}${t.isStyled ? '.styled' : ''}'
          '.${t.format.name}';
      try {
        await _api.downloadFile(t.url, p.join(dir, name));
        saved.add(
          DownloadedSubtitle(
            language: t.languageCode,
            fileName: name,
            format: t.format.name,
          ),
        );
      } on Object {
        // Without this one.
      }
    }
    return saved;
  }

  // ---------------------------------------------------------------------------
  // Controls

  Future<void> pause(String videoId) => _serial(() async {
    final d = await _store.get(videoId);
    if (d == null || !d.status.isActive) return;
    if (await _downloader.pause(videoId)) {
      await _store.put(d.copyWith(status: DownloadStatus.paused));
      _setProgress(videoId, null);
    }
  });

  /// Resumes a paused download, or tries a failed one again, with a fresh
  /// URL: from the partial file when there is one, else from the start.
  Future<void> resume(String videoId) => _serial(() => _resume(videoId));

  Future<void> _resume(String videoId) async {
    final d = await _store.get(videoId);
    if (d == null || d.status == DownloadStatus.complete) return;
    final String url;
    try {
      final sources = await _media.streams(videoId, fresh: true);
      final source =
          sources.where((s) => s.label == d.quality).firstOrNull ??
          pickQuality(sources, _height(d.quality));
      if (source == null) {
        await _fail(d, DownloadProblem.unavailable);
        return;
      }
      url = source.url;
      if (source.label != d.quality) {
        // The stored quality is gone; continue in the closest one. The
        // partial file is of the other quality, so start over.
        await _downloader.cancel(videoId);
        final moved = d.copyWith(
          quality: source.label,
          status: DownloadStatus.queued,
          clearProblem: true,
        );
        await _store.put(moved);
        if (!await _downloader.enqueue(_job(moved, url))) {
          await _fail(moved, DownloadProblem.unknown);
        }
        return;
      }
    } on Object {
      await _fail(d, DownloadProblem.network);
      return;
    }
    await _store.put(
      d.copyWith(status: DownloadStatus.queued, clearProblem: true),
    );
    if (await _downloader.resume(videoId, url)) return;
    if (!await _downloader.enqueue(_job(d, url))) {
      await _fail(d, DownloadProblem.unknown);
    }
  }

  /// Stops a download that isn't finished and removes it.
  Future<void> cancel(String videoId) => delete(videoId);

  /// Removes a download, finished or not: its video, its partial file, its
  /// subtitles and its row.
  Future<void> delete(String videoId) => _serial(() => _delete(videoId));

  Future<void> _delete(String videoId) async {
    final d = await _store.get(videoId);
    if (d == null) return;
    if (d.status.isActive) await _downloader.cancel(videoId);
    _setProgress(videoId, null);
    await _store.remove(videoId);
    final video = await _downloader.pathOf(_spot(d));
    final dir = p.dirname(video);
    for (final path in [
      video,
      for (final s in d.subtitles) p.join(dir, s.fileName),
    ]) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    try {
      final folder = Directory(dir);
      if (await folder.list().isEmpty) await folder.delete();
    } on FileSystemException {
      // Not empty, or gone.
    }
  }

  /// Removes every downloaded episode of [titleId] (or the movie).
  Future<void> deleteTitle(String titleId) => _serial(() async {
    for (final d in await _store.all()) {
      if (d.titleId == titleId) await _delete(d.videoId);
    }
  });

  // ---------------------------------------------------------------------------
  // Playing

  /// [videoId]'s downloaded file and subtitles, when it's complete and the
  /// file is still there.
  Future<LocalPlayback?> playable(String videoId) async {
    final d = await _store.get(videoId);
    if (d == null || d.status != DownloadStatus.complete) return null;
    final path = await _downloader.pathOf(_spot(d));
    if (!await File(path).exists()) return null;
    final dir = p.dirname(path);
    return LocalPlayback(
      path: path,
      quality: d.quality,
      subtitles: [
        for (final s in d.subtitles)
          if (File(p.join(dir, s.fileName)).existsSync())
            SubtitleTrack(
              url: Uri.file(p.join(dir, s.fileName)).toString(),
              languageCode: s.language,
              format:
                  SubtitleFormat.values.asNameMap()[s.format] ??
                  SubtitleFormat.srt,
            ),
      ],
    );
  }

  /// The downloaded episodes of [titleId], in order, for playing offline.
  Future<List<Episode>> downloadedEpisodes(String titleId) async {
    final episodes =
        [
          for (final d in await _store.all())
            if (d.titleId == titleId && d.status == DownloadStatus.complete)
              ?d.asEpisode,
        ]..sort(
          (a, b) => a.season != b.season
              ? a.season.compareTo(b.season)
              : a.episode.compareTo(b.episode),
        );
    return episodes;
  }

  /// The bytes the finished downloads take.
  Future<int> usedBytes() async => [
    for (final d in await _store.all())
      if (d.status == DownloadStatus.complete) d.totalBytes ?? 0,
  ].fold<int>(0, (a, b) => a + b);

  // ---------------------------------------------------------------------------
  // Engine events

  Future<void> _onEvent(DownloaderEvent event) async {
    final d = await _store.get(event.taskId);
    if (d == null) return;
    switch (event) {
      case DownloaderProgress():
        // Progress can trail a pause or a failure: it never changes those.
        if (d.status != DownloadStatus.queued &&
            d.status != DownloadStatus.running) {
          return;
        }
        _setProgress(
          d.videoId,
          DownloadProgress(
            fraction: event.fraction,
            expectedBytes: event.expectedBytes ?? d.totalBytes,
            bytesPerSecond: event.bytesPerSecond,
            timeLeft: event.timeLeft,
          ),
        );
        if (d.status == DownloadStatus.queued ||
            (d.totalBytes == null && event.expectedBytes != null)) {
          await _store.put(
            d.copyWith(
              status: DownloadStatus.running,
              totalBytes: event.expectedBytes,
            ),
          );
        }
      case DownloaderStatus(:final state):
        switch (state) {
          case DownloaderState.queued:
            if (d.status != DownloadStatus.queued) {
              await _store.put(d.copyWith(status: DownloadStatus.queued));
            }
          case DownloaderState.running:
            if (d.status != DownloadStatus.running) {
              await _store.put(
                d.copyWith(status: DownloadStatus.running, clearProblem: true),
              );
            }
          case DownloaderState.paused:
            _setProgress(d.videoId, null);
            await _store.put(d.copyWith(status: DownloadStatus.paused));
          case DownloaderState.complete:
            await _complete(d);
          case DownloaderState.canceled:
            _setProgress(d.videoId, null);
          case DownloaderState.failed:
            _setProgress(d.videoId, null);
            await _failed(d, event);
        }
    }
  }

  Future<void> _complete(Download d) async {
    _setProgress(d.videoId, null);
    _autoRetried.remove(d.videoId);
    int? size;
    try {
      size = await File(await _downloader.pathOf(_spot(d))).length();
    } on FileSystemException {
      size = d.totalBytes;
    }
    await _store.put(
      d.copyWith(
        status: DownloadStatus.complete,
        totalBytes: size,
        completedAt: _clock(),
        clearProblem: true,
      ),
    );
  }

  Future<void> _failed(Download d, DownloaderStatus e) async {
    final code = e.httpCode;
    // An expired or refused signed URL: try once more with a fresh one.
    if (code != null &&
        const {401, 403, 404, 410}.contains(code) &&
        _autoRetried.add(d.videoId)) {
      await _resume(d.videoId);
      return;
    }
    await _fail(
      d,
      e.noSpace
          ? DownloadProblem.noSpace
          : e.fileError
          ? DownloadProblem.storage
          : code != null && code >= 400 && code < 500
          ? DownloadProblem.unavailable
          : code == null
          ? DownloadProblem.network
          : DownloadProblem.unknown,
    );
  }

  Future<void> _fail(Download d, DownloadProblem problem) =>
      _store.put(d.copyWith(status: DownloadStatus.failed, problem: problem));

  static FileSpot _spot(Download d) =>
      FileSpot(d.baseDirectory, d.directory, d.fileName);

  static int _height(String quality) =>
      int.tryParse(RegExp(r'\d{3,4}').firstMatch(quality)?[0] ?? '') ?? 1080;

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// [name] as a file name on every platform: no path separators or
  /// characters Windows refuses, no trailing dots or spaces.
  static String _safe(String name, {required String fallback}) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }
}

/// The default desktop download folder: `~/Videos/Cinemakom`.
String defaultDesktopFolder() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return p.join(home, 'Videos', 'Cinemakom');
}

/// Where new downloads go on this platform (PLAN.md Phase 6): the
/// app-specific external folder on Android, Application Support on iOS,
/// and the chosen folder on desktop.
Future<DownloadRoot> platformDownloadRoot(String? desktopFolder) async {
  if (isDesktop) {
    return (
      baseDirectory: 'root',
      directory: desktopFolder ?? defaultDesktopFolder(),
    );
  }
  if (isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      return (
        baseDirectory: 'root',
        directory: p.join(external.path, 'Downloads'),
      );
    }
  }
  return (baseDirectory: 'applicationSupport', directory: 'Downloads');
}

final downloadStoreProvider = Provider<DownloadStore>(
  (ref) => DriftDownloadStore(ref.watch(appDatabaseProvider)),
);

/// Where new downloads go, asked at each download (the desktop folder can
/// change). Tests point it at a temporary folder.
final downloadRootProvider = Provider<Future<DownloadRoot> Function()>(
  (ref) =>
      () => platformDownloadRoot(ref.read(settingsProvider).downloadFolder),
);

final downloaderProvider = Provider<Downloader>(
  (ref) => BackgroundFileDownloader(),
);

/// Downloads for the whole app session (never disposed: it follows the
/// engine's events). Tests override [downloadStoreProvider] and
/// [downloaderProvider].
final downloadsRepositoryProvider = Provider<DownloadsRepository>(
  (ref) => DownloadsRepository(
    store: ref.watch(downloadStoreProvider),
    downloader: ref.watch(downloaderProvider),
    media: ref.watch(mediaRepositoryProvider),
    api: ref.watch(apiClientProvider),
    root: ref.watch(downloadRootProvider),
    styledSubtitles: !isAndroid,
  ),
);

final downloadsProvider = StreamProvider<List<Download>>(
  (ref) => ref.watch(downloadsRepositoryProvider).watchAll(),
);

final downloadProgressProvider = StreamProvider<Map<String, DownloadProgress>>(
  (ref) => ref.watch(downloadsRepositoryProvider).watchProgress(),
);

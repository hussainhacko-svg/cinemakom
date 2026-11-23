// The data models' own rules: what the UI and the player read from them.

import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_details.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/data/models/service_status.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';

const _min = Duration(minutes: 1);
const _s = Duration(seconds: 1);

Download _download({
  int? season,
  int? episode,
  int? episodeLast,
  bool finale = false,
  DownloadStatus status = DownloadStatus.running,
  int? totalBytes,
  int downloadedBytes = 0,
}) => Download(
  videoId: 'v',
  titleId: 't',
  title: const LocalizedText(en: 'T'),
  season: season,
  episode: episode,
  episodeLast: episodeLast,
  finale: finale,
  quality: '720p',
  baseDirectory: 'root',
  directory: '/d',
  fileName: 'f.mp4',
  status: status,
  addedAt: DateTime.utc(2026),
  totalBytes: totalBytes,
  downloadedBytes: downloadedBytes,
);

/// What DownloadsRepository saves for [episode] (kept in step with
/// `_download`): the server's number, and the last number only when it
/// differs.
Download _savedFor(Episode episode) => _download(
  season: episode.season,
  episode: episode.episode,
  episodeLast: episode.numbering.last == episode.episode
      ? null
      : episode.numbering.last,
  finale: episode.numbering.isFinale,
);

void main() {
  group('EpisodeNumbering.fromFlag', () {
    for (final (flag, numbers, finale) in [
      (null, [7], false),
      ('0000', [7], false),
      (' 1000 ', [7], true),
      ('0001', [6], false),
      ('1001', [6], true),
      ('0010', [7, 8], false),
      ('0020', [7, 8, 9], false),
      ('0100', [7, 8, 9], false),
      ('9999', [7], false),
      ('', [7], false),
    ]) {
      test('$flag → $numbers${finale ? ', final' : ''}', () {
        final n = EpisodeNumbering.fromFlag(7, flag);
        expect(n.numbers, numbers);
        expect(n.isFinale, finale);
      });
    }

    test('equality covers every field', () {
      expect(const EpisodeNumbering(1), const EpisodeNumbering(1));
      expect(
        const EpisodeNumbering(1) == const EpisodeNumbering(1, last: 2),
        isFalse,
      );
      expect(
        const EpisodeNumbering(1) == const EpisodeNumbering(1, isFinale: true),
        isFalse,
      );
    });

    // `1e300` rounds to the largest int. `n <= last` with `n++` then never
    // ended: the fuzz test grew to 10 GB and the kernel killed it.
    test('huge or wrapped numbers stay short and never empty', () {
      const max = 9223372036854775807;
      expect(const EpisodeNumbering(max).numbers, [max]);
      expect(const EpisodeNumbering(max - 1, last: max).numbers, [
        max - 1,
        max,
      ]);
      expect(EpisodeNumbering.fromFlag(max, '0010').numbers, [max]);
      expect(EpisodeNumbering.fromFlag(max, '0020').numbers, [max]);
      expect(EpisodeNumbering.fromFlag(-max - 1, '0001').numbers, [max]);
      expect(const EpisodeNumbering(1, last: max).numbers, [1, 2, 3]);
      expect(const EpisodeNumbering(5, last: 2).numbers, [5]);
    });
  });

  group('a downloaded episode keeps its label', () {
    // Every flag the server sends, saved and read back: the Downloads tab and
    // the offline player label the file from the row alone.
    for (final flag in [
      '0000',
      '1000',
      '0001',
      '1001',
      '0010',
      '0020',
      '0100',
    ]) {
      test('flag $flag', () {
        final live = Episode(
          id: 'v',
          season: 3,
          episode: 7,
          numbering: EpisodeNumbering.fromFlag(7, flag),
        );
        final saved = _savedFor(live);
        expect(saved.numbering, live.numbering);
        expect(saved.asEpisode!.numbering, live.numbering);
        expect(saved.asEpisode!.numbering.numbers, isNotEmpty);
        // Ordering still uses the server's number.
        expect(saved.asEpisode!.episode, 7);
      });
    }

    test('a movie has no episode', () {
      expect(_download().asEpisode, isNull);
      expect(_download().item.kind, VideoKind.movies);
      expect(_download(season: 1, episode: 2).item.kind, VideoKind.series);
    });
  });

  group('Download', () {
    test('savedFraction: 0–1, whatever the byte counts say', () {
      expect(
        _download(totalBytes: 100, downloadedBytes: 25).savedFraction,
        0.25,
      );
      expect(_download(totalBytes: 100, downloadedBytes: 500).savedFraction, 1);
      expect(_download(totalBytes: 0, downloadedBytes: 5).savedFraction, 0);
      expect(_download(totalBytes: -1, downloadedBytes: 5).savedFraction, 0);
      expect(_download(downloadedBytes: 5).savedFraction, 0);
      expect(
        _download(status: DownloadStatus.complete).savedFraction,
        1,
        reason: 'a finished download is whole even without sizes',
      );
    });

    test('waiting for a connection = paused, not by the user', () {
      final paused = _download(status: DownloadStatus.paused);
      expect(paused.isWaitingForConnection, isTrue);
      expect(
        paused.copyWith(pausedByUser: true).isWaitingForConnection,
        isFalse,
      );
      expect(_download().isWaitingForConnection, isFalse);
    });

    test('copyWith keeps everything it isn\'t told to change', () {
      final d = _download(totalBytes: 9).copyWith(
        problem: DownloadProblem.server,
        problemDetail: '500',
        contentUri: 'content://x',
      );
      final same = d.copyWith();
      expect(
        (same.problem, same.problemDetail),
        (DownloadProblem.server, '500'),
      );
      expect((same.totalBytes, same.contentUri), (9, 'content://x'));
      final cleared = d.copyWith(clearProblem: true);
      expect((cleared.problem, cleared.problemDetail), (null, null));
      expect(
        d.copyWith(clearProblemDetail: true).problem,
        DownloadProblem.server,
      );
    });

    test('only active rows are in the Downloading section', () {
      expect(DownloadStatus.values.where((s) => !s.isActive), [
        DownloadStatus.complete,
      ]);
    });

    test('DownloadedSubtitle JSON: round trip, and junk is refused', () {
      const s = DownloadedSubtitle(
        language: 'ar',
        fileName: 'a.srt',
        format: 'srt',
      );
      final back = DownloadedSubtitle.fromJson(s.toJson())!;
      expect(
        (back.language, back.fileName, back.format),
        ('ar', 'a.srt', 'srt'),
      );
      for (final junk in <Object?>[
        null,
        7,
        'x',
        [],
        {'lang': 'ar'},
        {'lang': 'ar', 'file': 3, 'format': 'srt'},
      ]) {
        expect(DownloadedSubtitle.fromJson(junk), isNull, reason: '$junk');
      }
    });
  });

  group('WatchProgress', () {
    WatchProgress at(Duration position, Duration duration, {bool? finished}) =>
        WatchProgress(
          videoId: 'v',
          position: position,
          duration: duration,
          updatedAt: DateTime.utc(2026),
          title: const LocalizedText(en: 'T'),
          finished: finished,
        );

    test('finished: 95%, or under 2 minutes left', () {
      expect(at(_min * 94, _min * 100).isFinished, isFalse);
      expect(at(_min * 95, _min * 100).isFinished, isTrue);
      expect(
        at(_min * 39, _min * 42).isFinished,
        isFalse,
        reason: '3 min left, 93%',
      );
      expect(at(_min * 41, _min * 42).isFinished, isTrue);
      expect(at(_min * 39, _min * 41).isFinished, isTrue);
    });

    test('a short video is not finished at its start', () {
      // Shorts and 1–3 minute anime episodes exist.
      expect(at(Duration.zero, _min).isFinished, isFalse);
      expect(at(_s * 10, _min * 3).isFinished, isFalse);
      expect(at(_s * 91, _min * 3).isFinished, isTrue, reason: 'past half');
      expect(at(_s * 58, _min).isFinished, isTrue, reason: '95%');
    });

    test('an unknown duration is never finished', () {
      expect(at(_min * 50, Duration.zero).isFinished, isFalse);
      expect(at(_min * 50, Duration.zero).fraction, 0);
    });

    test('a stored "finished" wins over the rule', () {
      expect(at(_min, _min * 100, finished: true).isFinished, isTrue);
      expect(at(_min * 99, _min * 100, finished: false).isFinished, isFalse);
    });

    test('resume only after 30 s and before the end', () {
      expect(at(_s * 29, _min * 100).resumeAt, isNull);
      expect(at(_s * 30, _min * 100).resumeAt, _s * 30);
      expect(at(_min * 99, _min * 100).resumeAt, isNull);
    });

    test('remaining and fraction stay in range past the end', () {
      final over = at(_min * 120, _min * 100);
      expect(over.remaining, Duration.zero);
      expect(over.fraction, 1);
      expect(at(-_min, _min * 100).fraction, 0);
    });

    test('item: the movie, or the series of an episode', () {
      final movie = at(_min, _min * 100);
      expect((movie.item.id, movie.item.kind), ('v', VideoKind.movies));
      final episode = WatchProgress(
        videoId: 'e2',
        seriesId: 's1',
        position: _min,
        duration: _min * 22,
        updatedAt: DateTime.utc(2026),
        title: const LocalizedText(en: 'S'),
      );
      expect((episode.item.id, episode.item.kind), ('s1', VideoKind.series));
      expect(episode.titleId, 's1');
    });
  });

  group('VideoSource', () {
    VideoSource src({
      String? name,
      String? resolution,
      String url = 'https://cdn/x.mp4',
    }) => VideoSource(url: url, name: name, resolution: resolution);

    test('height from the resolution or the name', () {
      expect(src(resolution: '1080p').height, 1080);
      expect(src(name: 'mp4-240').height, 240);
      expect(src(name: 'mp4-4k').height, 2160);
      expect(src(name: 'MP4-4K').height, 2160);
      expect(src(resolution: '2160p', name: 'mp4-4k').height, 2160);
      expect(src(resolution: '1920x1080').height, 1080);
      expect(src(resolution: '3840 × 2160').height, 2160);
      expect(src(resolution: 'auto').height, isNull);
      expect(src().height, isNull);
      expect(src().label, 'Auto');
    });

    test('expiry from a signed URL; absurd values are ignored', () {
      final now = DateTime.utc(2026, 11, 20);
      final in7h = now.add(const Duration(hours: 7));
      final signed = src(
        url:
            'https://cdn/x.mp4?Expires=${in7h.millisecondsSinceEpoch ~/ 1000}&Signature=a',
      );
      expect(signed.expiresAt, in7h);
      expect(signed.isValidFor(const Duration(hours: 6), now: now), isTrue);
      expect(signed.isValidFor(const Duration(hours: 8), now: now), isFalse);
      for (final raw in ['99999999999999999', 'soon', '', '-99999999999999']) {
        final s = src(url: 'https://cdn/x.mp4?Expires=$raw');
        expect(s.expiresAt, isNull, reason: raw);
        expect(s.isValidFor(const Duration(hours: 6), now: now), isTrue);
      }
      expect(src(url: 'not a url %%').expiresAt, isNull);
    });
  });

  group('SeekPreview.frameAt', () {
    const preview = SeekPreview([
      (url: 'a', rows: 10),
      (url: 'broken', rows: 0),
      (url: 'c', rows: 3),
    ]);

    test('row-major frames, 10 s each', () {
      expect(preview.frameAt(Duration.zero), (
        url: 'a',
        x: 0,
        y: 0,
        width: 120,
        height: 68,
      ));
      expect(preview.frameAt(_s * 19)!.x, 120);
      expect(preview.frameAt(_s * 100), (
        url: 'a',
        x: 0,
        y: 68,
        width: 120,
        height: 68,
      ));
      expect(preview.frameAt(_s * 999)!.y, 9 * 68);
    });

    test(
      'a broken sheet, a short last sheet, the end and before the start',
      () {
        expect(preview.frameAt(_s * 1000), isNull, reason: 'broken sheet');
        expect(preview.frameAt(_s * 2000)!.url, 'c');
        expect(preview.frameAt(_s * 2299)!.y, 2 * 68);
        expect(preview.frameAt(_s * 2300), isNull, reason: 'past the last row');
        expect(preview.frameAt(_s * 99999), isNull);
        expect(preview.frameAt(-_s), isNull);
        expect(const SeekPreview([]).frameAt(Duration.zero), isNull);
        expect(preview.sheetUrls, ['a', 'c']);
      },
    );
  });

  test('oneTrackPerLanguage: one plain track each, srt preferred, styled '
      'last', () {
    const vtt = SubtitleTrack(
      url: 'u1',
      languageCode: 'ar',
      format: SubtitleFormat.vtt,
    );
    const srt = SubtitleTrack(url: 'u2', languageCode: 'ar');
    const en = SubtitleTrack(
      url: 'u3',
      languageCode: 'en',
      format: SubtitleFormat.vtt,
    );
    const ass = SubtitleTrack(
      url: 'u4',
      languageCode: 'ar',
      format: SubtitleFormat.ass,
    );
    const ass2 = SubtitleTrack(
      url: 'u5',
      languageCode: 'ar',
      format: SubtitleFormat.ass,
    );
    expect(oneTrackPerLanguage([ass, vtt, en, srt, ass2]), [srt, en, ass]);
    expect(oneTrackPerLanguage([vtt, srt], prefer: SubtitleFormat.vtt), [vtt]);
    expect(oneTrackPerLanguage([]), isEmpty);
  });

  group('youtubeVideoId', () {
    for (final (url, id) in [
      ('https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
      ('https://youtube.com/watch?feature=x&v=dQw4w9WgXcQ&t=1', 'dQw4w9WgXcQ'),
      (
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&ab;_channel=X',
        'dQw4w9WgXcQ',
      ),
      ('https://youtu.be/dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
      ('https://m.youtube.com/embed/dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
      ('https://www.youtube.com/shorts/dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
      ('https://vimeo.com/12345678', null),
      ('https://www.youtube.com/watch?v=', null),
      ('https://www.youtube.com/watch?v=<script>', null),
      ('https://evil-youtube.com.example/watch?v=dQw4w9WgXcQ', null),
      ('', null),
      (null, null),
    ]) {
      test('$url', () => expect(youtubeVideoId(url), id));
    }
  });

  test('imdbUrlIsImdb only for imdb.com', () {
    MediaDetails d(String? url) => MediaDetails(
      item: const MediaItem(id: '1'),
      imdbUrl: url,
    );
    expect(d('https://www.imdb.com/title/tt1/').imdbUrlIsImdb, isTrue);
    expect(d('https://myanimelist.net/anime/1').imdbUrlIsImdb, isFalse);
    expect(d(null).imdbUrlIsImdb, isFalse);
  });

  test('SkipRange contains its start, not its end', () {
    const r = SkipRange(Duration(seconds: 10), Duration(seconds: 70));
    expect(r.contains(const Duration(seconds: 10)), isTrue);
    expect(r.contains(const Duration(seconds: 69)), isTrue);
    expect(r.contains(const Duration(seconds: 70)), isFalse);
    expect(r.length, const Duration(minutes: 1));
  });

  test('PlaybackRequest: the episode\'s ID, else the linked one, else the '
      'item', () {
    const series = MediaItem(id: 's', kind: VideoKind.series);
    final e = Episode(id: 'e', season: 1, episode: 1);
    expect(PlaybackRequest(item: series, episode: e).videoId, 'e');
    expect(const PlaybackRequest(item: series, episodeId: 'x').videoId, 'x');
    expect(const PlaybackRequest(item: MediaItem(id: 'm')).videoId, 'm');
    expect(const PlaybackRequest(item: MediaItem(id: 'm')).isSeries, isFalse);
    expect(
      const PlaybackRequest(
        item: MediaItem(id: 'm'),
        episodeId: 'x',
      ).isSeries,
      isTrue,
    );
    expect(
      PlaybackRequest(item: series, episode: e),
      PlaybackRequest(
        item: series,
        episode: Episode(id: 'e', season: 9, episode: 9),
      ),
    );
    expect(
      const PlaybackRequest(item: series, start: Duration.zero) ==
          const PlaybackRequest(item: series),
      isFalse,
    );
  });

  test('MediaItem: seriesId, copyWith, LocalizedText fallbacks', () {
    const ep = MediaItem(id: 'e', rootSeriesId: 's', hdPosterUrl: 'hd');
    expect(ep.seriesId, 's');
    expect(const MediaItem(id: 'm').seriesId, 'm');
    final c = ep.copyWith(
      kind: VideoKind.series,
      clearHdPoster: true,
      linkedEpisodeId: 'l',
    );
    expect(
      (c.kind, c.hdPosterUrl, c.linkedEpisodeId, c.rootSeriesId),
      (VideoKind.series, null, 'l', 's'),
    );
    const t = LocalizedText(en: 'A');
    expect((t.resolve(arabic: true), t.resolve(arabic: false)), ('A', 'A'));
    expect(const LocalizedText(ar: 'ب').resolve(arabic: false), 'ب');
    expect(const LocalizedText().isEmpty, isTrue);
  });

  test('ServiceHealth: down only for outages and maintenance', () {
    expect(ServiceHealth.values.where((h) => h.isDown).toSet(), {
      ServiceHealth.partialOutage,
      ServiceHealth.majorOutage,
      ServiceHealth.underMaintenance,
    });
  });
}

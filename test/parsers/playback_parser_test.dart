import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/parsers/playback_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixture.dart';

void main() {
  group('video sources', () {
    test('fixtures are sorted highest first', () {
      for (final name in ['streams_movie', 'streams_episode']) {
        final sources = parseVideoSources(fixture(name));
        expect(sources, isNotEmpty, reason: name);
        final heights = sources.map((s) => s.height!).toList();
        expect(heights, [...heights]..sort((a, b) => b.compareTo(a)));
        expect(sources.every((s) => s.url.startsWith('https://')), isTrue);
      }
    });

    test('skips entries without a real URL and duplicates', () {
      final sources = parseVideoSources([
        {'resolution': '720p', 'videoUrl': 'https://x/720.mp4'},
        {'resolution': '720p', 'videoUrl': 'https://x/720.mp4'},
        {'resolution': '480p', 'videoUrl': ''},
        {'resolution': '360p'},
        'garbage',
      ]);
      expect(sources.single.height, 720);
    });

    test('pickClosestQuality', () {
      VideoSource s(String r) =>
          VideoSource(url: 'https://x/$r', resolution: r);
      final list = [s('1080p'), s('720p'), s('480p')];
      expect(pickClosestQuality(list, 720)!.height, 720);
      expect(pickClosestQuality(list, 2160)!.height, 1080);
      expect(pickClosestQuality(list, 600)!.height, 480);
      expect(pickClosestQuality(list, 360)!.height, 480);
      expect(pickClosestQuality(const [], 720), isNull);
    });
  });

  group('subtitles', () {
    test('movie fixture: Arabic and English, each as srt and vtt', () {
      final tracks = parseSubtitles(fixture('subtitles_movie'));
      expect(tracks.map((t) => t.languageCode).toSet(), {'ar', 'en'});
      expect(
        tracks.map((t) => t.format).toSet(),
        SubtitleFormat.values.toSet(),
      );
      final picked = oneTrackPerLanguage(tracks);
      expect(picked.map((t) => t.languageCode), ['ar', 'en']);
      expect(picked.every((t) => t.format == SubtitleFormat.srt), isTrue);
      expect(
        oneTrackPerLanguage(
          tracks,
          prefer: SubtitleFormat.vtt,
        ).every((t) => t.format == SubtitleFormat.vtt),
        isTrue,
      );
    });

    test('rejects the loading.gif placeholder', () {
      final tracks = parseSubtitles({
        'arTranslationFile': '',
        'arTranslationFilePath': 'defaultImages/loading.gif',
        'enTranslationFilePath': 'https://x/loading.gif',
      });
      expect(tracks, isEmpty);
    });

    test('translations list: type, name and extention spelling', () {
      final tracks = parseSubtitles({
        'translations': [
          {
            'name': 'arabic',
            'type': 'ar',
            'extention': 'srt',
            'file': r'https:\/\/x\/a.srt?sig=1',
          },
          {'name': 'English', 'extension': '.vtt', 'file': 'https://x/e.vtt'},
          {'name': 'arabic', 'type': 'ar', 'file': 'https://x/a.srt?sig=2'},
        ],
        'arTranslationFilePath': 'https://x/other-ar.srt',
      });
      expect(tracks, hasLength(2));
      expect(tracks[0].languageCode, 'ar');
      expect(tracks[0].url, 'https://x/a.srt?sig=1');
      expect(tracks[1].languageCode, 'en');
      expect(tracks[1].format, SubtitleFormat.vtt);
    });

    test('bare list and junk input', () {
      expect(
        parseSubtitles([
          {'type': 'en', 'url': 'https://x/e.srt'},
        ]),
        hasLength(1),
      );
      expect(parseSubtitles(null), isEmpty);
      expect(parseSubtitles(42), isEmpty);
    });
  });

  group('episodes and seasons', () {
    test('fixture is de-duplicated and sorted by season then episode', () {
      final eps = parseEpisodes(fixture('series_episodes'));
      expect(eps, isNotEmpty);
      for (var i = 1; i < eps.length; i++) {
        final a = eps[i - 1], b = eps[i];
        expect(
          a.season < b.season ||
              (a.season == b.season && a.episode < b.episode),
          isTrue,
          reason: '$a before $b',
        );
      }
      expect(eps.map((e) => e.id).toSet(), hasLength(eps.length));
    });

    test('missing numbers fall back, digit-only titles are dropped', () {
      final eps = parseEpisodes({
        'episodes': [
          {'nb': '10', 'en_title': '12'},
          {
            'nb': '11',
            'season': 'S2',
            'episodeNummer': '3',
            'ar_title': 'حلقة',
          },
          {'nb': '10', 'en_title': 'dup'},
          {'title': 'no id'},
        ],
      });
      expect(eps.map((e) => (e.id, e.season, e.episode)), [
        ('10', 1, 1),
        ('11', 2, 3),
      ]);
      expect(eps.first.title.isEmpty, isTrue);
      expect(eps.last.title.ar, 'حلقة');
    });

    test('seasons fixture and junk', () {
      final seasons = parseSeasons(fixture('series_seasons'));
      expect(seasons, isNotEmpty);
      expect(seasons, [...seasons]..sort());
      expect(
        parseSeasons([
          {'season': '2'},
          {'season': '1'},
          {'season': '2'},
          {'season': '0'},
          'x',
        ]),
        [1, 2],
      );
    });
  });

  test('episodes that all repeat the series name get no title', () {
    final eps = parseEpisodes(fixture('series_episodes'));
    expect(eps.every((e) => e.title.isEmpty), isTrue);
    final distinct = parseEpisodes([
      {'nb': '1', 'en_title': 'Pilot'},
      {'nb': '2', 'en_title': 'The Sequel'},
    ]);
    expect(distinct.map((e) => e.title.en), ['Pilot', 'The Sequel']);
  });

  group('seek preview', () {
    test('fixture sheets are ordered absolute URLs', () {
      final preview = parseSeekPreview(fixture('thumbnails'))!;
      expect(preview.sheetUrls, isNotEmpty);
      expect(preview.sheetUrls.first, endsWith('_0.png'));
      expect(preview.sheetUrls.every((u) => u.startsWith('https://')), isTrue);
    });

    test('no previews', () {
      expect(parseSeekPreview(fixture('thumbnails_none')), isNull);
      expect(parseSeekPreview(null), isNull);
    });

    test('relative URLs fall back to the image host, order is respected', () {
      final preview = parseSeekPreview({
        'videoThumbnails': [
          {'url': 'vascin-video-thumbnails/9_1.png', 'order': '1'},
          {'url': 'vascin-video-thumbnails/9_0.png', 'order': '0'},
        ],
      })!;
      expect(preview.sheetUrls, [
        'https://cnth2.shabakaty.com/vascin-video-thumbnails/9_0.png',
        'https://cnth2.shabakaty.com/vascin-video-thumbnails/9_1.png',
      ]);
    });

    test('frameAt maps time to sheet and cell (10 s, 10×10 grid)', () {
      const p = SeekPreview(['a', 'b']);
      expect(p.frameAt(Duration.zero), (
        url: 'a',
        x: 0,
        y: 0,
        width: 120,
        height: 68,
      ));
      expect(p.frameAt(const Duration(seconds: 125)), (
        url: 'a',
        x: 240,
        y: 68,
        width: 120,
        height: 68,
      ));
      expect(p.frameAt(const Duration(seconds: 1000)), (
        url: 'b',
        x: 0,
        y: 0,
        width: 120,
        height: 68,
      ));
      expect(p.frameAt(const Duration(seconds: 2000)), isNull);
    });
  });
}

import 'package:cinemakom/data/models/media_item.dart';
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

    test('quality classes, including the "m480" and "mp4-4k" names', () {
      expect(const VideoSource(url: 'u', name: 'm480').height, 480);
      expect(const VideoSource(url: 'u', name: 'mp4-4k').height, 2160);
      expect(
        const VideoSource(url: 'u', name: 'mp4-4k', resolution: '2160p').height,
        2160,
      );
      expect(const VideoSource(url: 'u').height, isNull);
    });

    test('signed URL expiry', () {
      const signed = VideoSource(
        url: 'https://cdn.shabakaty.com/v.mp4?AWSAccessKeyId=K&Expires=2000000000&Signature=S',
      );
      final expires = DateTime.utc(2033, 5, 18, 3, 33, 20);
      expect(signed.expiresAt, expires);
      final before = expires.subtract(const Duration(hours: 7));
      expect(signed.isValidFor(const Duration(hours: 6), now: before), isTrue);
      expect(
        signed.isValidFor(
          const Duration(hours: 6),
          now: expires.subtract(const Duration(hours: 5)),
        ),
        isFalse,
      );
      const unsigned = VideoSource(url: 'https://x/v.mp4');
      expect(unsigned.expiresAt, isNull);
      expect(
        unsigned.isValidFor(const Duration(days: 1), now: DateTime.now()),
        isTrue,
      );
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
      expect(tracks.map((t) => t.format).toSet(), {
        SubtitleFormat.srt,
        SubtitleFormat.vtt,
      });
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

    test('special (ass) fixtures become styled Arabic tracks', () {
      for (final name in ['subtitles_special', 'video_info_special']) {
        final tracks = parseSubtitles(fixture(name));
        final styled = tracks.where((t) => t.isStyled).toList();
        expect(styled, hasLength(1), reason: name);
        expect(styled.single.languageCode, 'ar', reason: name);
        expect(styled.single.format, SubtitleFormat.ass, reason: name);
        expect(styled.single.url, contains('.ass'), reason: name);
        // The plain Arabic track is still there, once per format.
        expect(
          tracks.where((t) => t.languageCode == 'ar' && !t.isStyled),
          hasLength(2),
          reason: name,
        );
        final picked = oneTrackPerLanguage(tracks);
        expect(picked.where((t) => !t.isStyled).map((t) => t.format), [
          SubtitleFormat.srt,
        ], reason: name);
        expect(picked.last.isStyled, isTrue, reason: name);
      }
    });

    test('ass entries in both spellings', () {
      final tracks = parseSubtitles({
        'translations': [
          {
            'type': 'sp',
            'name': 'special',
            'extention': 'ass',
            'file': 'https://x/a_sp_transfile.ass',
          },
          {
            'type': 'arabic',
            'name': 'arabic',
            'extention': 'ass',
            'file': 'https://x/b_sp_transfile.ass',
          },
          {'type': 'x', 'file': 'https://x/c.ass'},
        ],
      });
      expect(tracks.map((t) => (t.languageCode, t.format)), [
        ('ar', SubtitleFormat.ass),
        ('ar', SubtitleFormat.ass),
        ('ar', SubtitleFormat.ass),
      ]);
      // Only one styled track per language is offered.
      expect(oneTrackPerLanguage(tracks), hasLength(1));
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

    test('missing numbers fall back, duplicates and bad entries go', () {
      final eps = parseEpisodes({
        'episodes': [
          {'nb': '10', 'en_title': '12'},
          {'nb': '11', 'season': 'S2', 'episodeNummer': '3'},
          {'nb': '10', 'en_title': 'dup'},
          {'title': 'no id'},
        ],
      });
      expect(eps.map((e) => (e.id, e.season, e.episode)), [
        ('10', 1, 1),
        ('11', 2, 3),
      ]);
      expect(eps.last.numbering, const EpisodeNumbering(3));
    });

    test('episode_flag fixtures: finales and double episodes', () {
      final finale = parseEpisodes(fixture('series_episodes_finale'));
      expect(finale.where((e) => e.numbering.isFinale), isNotEmpty);
      expect(finale.where((e) => !e.numbering.isFinale), isNotEmpty);

      final double = parseEpisodes(fixture('series_episodes_double'));
      final two = double.firstWhere((e) => e.numbering.last > e.episode);
      expect(two.numbering.numbers, [two.episode, two.episode + 1]);
      expect(double.where((e) => e.numbering.last == e.episode), isNotEmpty);
    });

    test('every episode_flag the website knows', () {
      EpisodeNumbering n(String flag) => EpisodeNumbering.fromFlag(10, flag);
      expect(n('0000'), const EpisodeNumbering(10));
      expect(n('1000'), const EpisodeNumbering(10, isFinale: true));
      expect(n('0001'), const EpisodeNumbering(9));
      expect(n('1001'), const EpisodeNumbering(9, isFinale: true));
      expect(n('0010'), const EpisodeNumbering(10, last: 11));
      expect(n('0020').numbers, [10, 11, 12]);
      expect(n('0100').numbers, [10, 11, 12]);
      expect(n('9999'), const EpisodeNumbering(10));
      expect(EpisodeNumbering.fromFlag(10, null), const EpisodeNumbering(10));
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

  group('seek preview', () {
    test('fixture sheets are ordered absolute URLs with row counts', () {
      final preview = parseSeekPreview(fixture('thumbnails'))!;
      expect(preview.sheetUrls, isNotEmpty);
      expect(preview.sheetUrls.first, endsWith('_0.png'));
      expect(preview.sheetUrls.every((u) => u.startsWith('https://')), isTrue);
      expect(preview.sheets.first.rows, SeekPreview.maxRows);
      expect(preview.sheets.every((s) => s.rows > 0 && s.rows <= 10), isTrue);
    });

    test('no previews, or only a broken sheet', () {
      expect(parseSeekPreview(fixture('thumbnails_none')), isNull);
      expect(parseSeekPreview(fixture('thumbnails_broken')), isNull);
      expect(parseSeekPreview(null), isNull);
    });

    test('height gives the rows; 0 keeps a broken sheet in place', () {
      final preview = parseSeekPreview({
        'videoThumbnails': [
          {'sprite_url': 'https://x/0.png', 'order': '0', 'height': '680'},
          {'sprite_url': 'https://x/1.png', 'order': '1', 'height': '0'},
          {'sprite_url': 'https://x/2.png', 'order': '2', 'height': '408'},
        ],
      })!;
      expect(preview.sheets.map((s) => s.rows), [10, 0, 6]);
      expect(preview.sheetUrls, ['https://x/0.png', 'https://x/2.png']);
      expect(
        preview.frameAt(const Duration(seconds: 999))!.url,
        'https://x/0.png',
      );
      expect(preview.frameAt(const Duration(seconds: 1500)), isNull);
      expect(preview.frameAt(const Duration(seconds: 2590))!.y, 5 * 68);
      // Row 6 of the last sheet does not exist.
      expect(preview.frameAt(const Duration(seconds: 2600)), isNull);
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
      const p = SeekPreview([(url: 'a', rows: 10), (url: 'b', rows: 10)]);
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

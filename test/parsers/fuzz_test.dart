// Fuzzing every parser: random JSON built from the API's own keys and the
// values that break naive code, and real fixtures with fields randomly
// broken. The rule (AGENTS.md) is that parsers skip bad items and never
// throw; the invariants check that what they return is still sound.
//
// Seeded, so a failure repeats: the reason names the seed and the case.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cinemakom/core/json/json_utils.dart';
import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/data/models/catalog_models.dart';
import 'package:cinemakom/data/models/media_details.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/parsers/category_parser.dart';
import 'package:cinemakom/data/parsers/details_parser.dart';
import 'package:cinemakom/data/parsers/media_parser.dart';
import 'package:cinemakom/data/parsers/playback_parser.dart';
import 'package:cinemakom/data/parsers/status_parser.dart';
import 'package:cinemakom/data/repositories/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// How many random documents each parser gets.
const _cases = 1500;

/// Every key the parsers read, so random maps hit real code paths.
const _keys = [
  'nb',
  'id',
  'video_id',
  'target_id',
  'itemId',
  'en_title',
  'ar_title',
  'title',
  'title_en',
  'title_ar',
  'name',
  'videoTitle',
  'arabicTitle',
  'other_title',
  'otherTitle',
  'imgMediumThumbObjUrl',
  'imgMediumObjUrl',
  'imgObjUrl',
  'imgThumbObjUrl',
  'poster',
  'posterUrl',
  'image',
  'backgroundImageObjUrl',
  'backdropUrl',
  'coverUrl',
  'year',
  'releaseYear',
  'mDate',
  'kind',
  'videoKind',
  'type',
  'rootSeries',
  'season',
  'episodeNummer',
  'episodeNumber',
  'episode_number',
  'episode',
  'episode_flag',
  'categories',
  'genres',
  'subCategories',
  'duration',
  'en_content',
  'ar_content',
  'description',
  'story',
  'data',
  'info',
  'videos',
  'items',
  'results',
  'content',
  'list',
  'movies',
  'series',
  'groups',
  'groupsID',
  'hasPagination',
  'link',
  'offset',
  'directorsInfo',
  'actorsInfo',
  'writersInfo',
  'staff_img',
  'staff_img_thumb',
  'staff_img_medium_thumb',
  'staffID',
  'role',
  'videoLanguages',
  'trailer',
  'imdbUrlRef',
  'introSkipping',
  'start',
  'end',
  'castable',
  'translations',
  'files',
  'file',
  'filePath',
  'url',
  'subtitleUrl',
  'src',
  'extention',
  'extension',
  'lang',
  'language',
  'arTranslationFilePath',
  'enTranslationFilePath',
  'videoUrl',
  'resolution',
  'container',
  'transcoddedFileName',
  'videoThumbnails',
  'sprite_url',
  'order',
  'height',
  'status',
  'components',
  'group_id',
  'langArray',
  'catNb',
  'langNb',
  'lang_en_title',
  'lang_ar_title',
  'langFreq',
  'langFreqSeries',
  'porder',
  'priority',
  'categoryName',
  'children',
  'categoryID',
];

/// Strings that have broken parsers somewhere.
final _nastyStrings = [
  '',
  ' ',
  '\t\n',
  'null',
  'NULL',
  'undefined',
  '0',
  '00',
  '-1',
  '1',
  '12',
  '2026',
  '1e400',
  '-1e400',
  'NaN',
  'Infinity',
  '1.5',
  '7.5/10',
  '99999999999999999999999',
  'S02',
  '١٢٣',
  '0001',
  '1001',
  '0010',
  '0020',
  'true',
  'false',
  'yes',
  'series',
  'movies',
  '1',
  '2',
  'sp',
  'special',
  'arabic',
  'english',
  'ar',
  'en',
  'srt',
  'vtt',
  'ass',
  '.srt',
  'عربي',
  'https://cnth2.shabakaty.com/vascin-poster-images/a.jpg',
  r'https:\/\/cnth2.shabakaty.com\/vascin-poster-images\/b.jpg',
  'https://cdn.example/v.mp4?Expires=99999999999999999&Signature=x',
  'https://cdn.example/v.mp4?Expires=1795089600',
  'https://cdn.example/sub.ar.srt',
  'https://cdn.example/x.gif',
  'https://cnth2.shabakaty.com/loadingImages/loading.gif',
  'defaultImages/loading.gif',
  'vascin-poster-images/c.jpg',
  '/vascin-x.png',
  'http://',
  'https://',
  '://nohost',
  'ftp://x/y.mp4',
  '%%%',
  'http://[::1',
  'mp4-1080',
  'mp4-4k',
  '1080p',
  '2160p',
  '1920x1080',
  'operational',
  'major_outage',
  'Cinemana',
  'cinemana',
  'operational ',
  'https://cinemana.shabakaty.cc/video/ar/797119?lastEpisodeVideoID=3157016',
  'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  '\u0000',
  '\u202e',
  '🎬🎬🎬',
  'a' * 5000,
];

class _Gen {
  _Gen(this.seed) : _r = Random(seed);
  final int seed;
  final Random _r;

  Object? value(int depth) {
    final roll = _r.nextInt(depth > 3 ? 6 : 10);
    return switch (roll) {
      0 => null,
      1 => _r.nextBool(),
      2 => _int(),
      3 => _double(),
      4 || 5 => _nastyStrings[_r.nextInt(_nastyStrings.length)],
      6 || 7 => map(depth + 1),
      _ => list(depth + 1),
    };
  }

  int _int() => switch (_r.nextInt(6)) {
    0 => 0,
    1 => -_r.nextInt(1000),
    2 => 1 << 62,
    3 => -(1 << 62),
    _ => _r.nextInt(5000),
  };

  double _double() => switch (_r.nextInt(5)) {
    0 => 1e300,
    1 => -1e300,
    2 => 0.5,
    3 => 1e-300,
    _ => _r.nextDouble() * 10000,
  };

  Map<String, Object?> map(int depth) => {
    for (var i = 0, n = _r.nextInt(8); i < n; i++)
      _keys[_r.nextInt(_keys.length)]: value(depth),
  };

  List<Object?> list(int depth) => [
    for (var i = 0, n = _r.nextInt(6); i < n; i++) value(depth),
  ];

  Object? document() =>
      _r.nextInt(4) == 0 ? value(0) : (_r.nextBool() ? list(0) : map(0));

  /// [json] with leaves replaced, keys dropped and types swapped.
  Object? mutate(Object? json, {int depth = 0}) {
    if (depth > 8) return json;
    if (_r.nextInt(12) == 0) return value(3);
    if (json is Map) {
      return {
        for (final e in json.entries)
          if (_r.nextInt(15) != 0)
            '${e.key}': mutate(e.value, depth: depth + 1),
      };
    }
    if (json is List) {
      final out = [for (final v in json) mutate(v, depth: depth + 1)];
      if (out.isNotEmpty && _r.nextInt(10) == 0) out.add(value(2));
      return out;
    }
    return _r.nextInt(5) == 0 ? value(3) : json;
  }
}

/// Parses with [parse] and checks [invariants] on the result, for random
/// documents and for mutated copies of [fixtures].
void _fuzz<T>(
  String name,
  T Function(Object? json) parse, {
  List<String> fixtures = const [],
  void Function(T result, String why)? invariants,
}) {
  test('$name never throws and keeps its guarantees', () {
    // One document at a time: holding them all (60 mutated copies of every
    // fixture) takes far more memory than the test needs.
    void check(String why, Object? doc) {
      final T result;
      try {
        result = parse(doc);
      } catch (e, s) {
        fail('$name threw on $why: $e\n$s');
      }
      invariants?.call(result, why);
    }

    for (var seed = 0; seed < _cases; seed++) {
      check('random seed $seed', _Gen(seed).document());
    }
    for (final f in fixtures) {
      final raw = jsonDecode(File('test/fixtures/$f.json').readAsStringSync());
      check('fixture $f', raw);
      for (var seed = 0; seed < 60; seed++) {
        check('fixture $f mutated seed $seed', _Gen(seed).mutate(raw));
      }
    }
  });
}

bool _isHttpOrNull(String? url) => url == null || isHttpUrl(url);

void _mediaItemInvariants(List<MediaItem> items, String why) {
  final ids = <String>{};
  for (final i in items) {
    expect(ids.add(i.id), isTrue, reason: '$why: duplicate ${i.id}');
    expect(readId(i.id), i.id, reason: '$why: bad id "${i.id}"');
    expect(i.title.isEmpty, isFalse, reason: '$why: untitled ${i.id}');
    for (final url in [i.posterUrl, i.hdPosterUrl, i.backdropUrl]) {
      expect(_isHttpOrNull(url), isTrue, reason: '$why: url $url');
      expect(isPlaceholderImage(url), isFalse, reason: '$why: $url');
    }
    if (i.year != null) expect(i.year, greaterThan(1800), reason: why);
    if (i.season != null) expect(i.season, greaterThan(0), reason: why);
    if (i.episode != null) expect(i.episode, greaterThan(0), reason: why);
    if (i.duration != null) {
      expect(
        i.duration! > Duration.zero,
        isTrue,
        reason: '$why: ${i.duration}',
      );
    }
    if (i.numbering != null) {
      expect(i.numbering!.numbers, isNotEmpty, reason: why);
    }
  }
}

void main() {
  group('json helpers', () {
    test('never throw on any value', () {
      for (var seed = 0; seed < _cases * 4; seed++) {
        final v = _Gen(seed).value(0);
        final m = asMap(v) ?? const {};
        try {
          asList(v);
          readString(v);
          parseIntLoose(v);
          parseDoubleLoose(v);
          parseBoolLoose(v);
          readId(v);
          final s = readString(v);
          isHttpUrl(s);
          isPlaceholderImage(s);
          realImageUrl(s);
          resolveImageUrl(s);
          firstNonBlank(m, _keys);
          readUrl(m, _keys);
          if (s != null) signedUrlExpiry(s);
          parseSeconds(v);
          durationFromSeconds(parseDoubleLoose(v));
        } catch (e, s) {
          fail('threw on seed $seed ($v): $e\n$s');
        }
      }
    });

    test('numbers stay finite and durations positive', () {
      for (var seed = 0; seed < _cases * 4; seed++) {
        final v = _Gen(seed).value(0);
        final d = parseDoubleLoose(v);
        if (d != null) expect(d.isFinite, isTrue, reason: '$v');
        final s = parseSeconds(v);
        if (s != null) expect(s > Duration.zero, isTrue, reason: '$v → $s');
      }
    });
  });

  _fuzz(
    'parseMediaItems',
    parseMediaItems,
    fixtures: [
      'latest_movies',
      'latest_series',
      'featured',
      'newly_added',
      'catalog_movies_most_viewed',
      'catalog_series_newest',
      'title_search',
      'advanced_search_series',
      'videos_by_ids',
      'related_movie',
      'recommendations',
      'video_group_page',
      'videos_by_category',
    ],
    invariants: _mediaItemInvariants,
  );

  _fuzz(
    'parseMediaItems with a fallback kind',
    (j) => parseMediaItems(j, fallbackKind: VideoKind.series),
    invariants: (items, why) {
      _mediaItemInvariants(items, why);
      for (final i in items) {
        expect(i.kind, isNotNull, reason: why);
      }
    },
  );

  _fuzz(
    'parseBanners',
    parseBanners,
    fixtures: ['banners'],
    invariants: (items, why) {
      _mediaItemInvariants(items, why);
      for (final i in items) {
        expect(i.hdPosterUrl, isNull, reason: why);
        if (i.linkedEpisodeId != null) {
          expect(readId(i.linkedEpisodeId), i.linkedEpisodeId, reason: why);
        }
      }
    },
  );

  _fuzz<List<VideoGroup>>(
    'parseVideoGroups',
    parseVideoGroups,
    fixtures: ['video_groups_en', 'video_groups_ar'],
    invariants: (groups, why) {
      for (final g in groups) {
        expect(g.items, isNotEmpty, reason: why);
        expect(g.title.trim(), isNotEmpty, reason: why);
        _mediaItemInvariants(g.items, why);
      }
    },
  );

  _fuzz<OffsetPage>(
    'parseOffsetPage',
    parseOffsetPage,
    fixtures: ['videos_by_category', 'videos_by_category_and_language'],
    invariants: (page, why) {
      _mediaItemInvariants(page.items, why);
      if (page.hasMore) {
        expect(page.items, isNotEmpty, reason: '$why: more after nothing');
      }
    },
  );

  _fuzz<MediaDetails?>(
    'parseMediaDetails',
    parseMediaDetails,
    fixtures: [
      'video_info_movie',
      'video_info_series',
      'video_info_episode',
      'video_info_special',
    ],
    invariants: (d, why) {
      if (d == null) return;
      _mediaItemInvariants([d.item], why);
      for (final list in [d.actors, d.directors, d.writers]) {
        expect({for (final c in list) c.id}.length, list.length, reason: why);
        for (final c in list) {
          expect(_isHttpOrNull(c.imageUrl), isTrue, reason: why);
        }
      }
      expect(_isHttpOrNull(d.trailerUrl), isTrue, reason: why);
      expect(_isHttpOrNull(d.imdbUrl), isTrue, reason: why);
      for (var i = 0; i < d.introRanges.length; i++) {
        final r = d.introRanges[i];
        expect(r.start >= Duration.zero, isTrue, reason: why);
        expect(r.length >= const Duration(seconds: 1), isTrue, reason: why);
        if (i > 0) {
          expect(r.start >= d.introRanges[i - 1].start, isTrue, reason: why);
        }
      }
      d.trailerYoutubeId;
      d.imdbUrlIsImdb;
    },
  );

  _fuzz<List<VideoSource>>(
    'parseVideoSources',
    parseVideoSources,
    fixtures: ['streams_movie', 'streams_episode'],
    invariants: (sources, why) {
      final urls = <String>{};
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        expect(isHttpUrl(s.url), isTrue, reason: why);
        expect(urls.add(s.url), isTrue, reason: '$why: duplicate');
        s.expiresAt;
        s.label;
        if (i > 0) {
          expect(
            (sources[i - 1].height ?? -1) >= (s.height ?? -1),
            isTrue,
            reason: '$why: not highest first',
          );
        }
      }
      for (final h in [0, 240, 720, 1080, 2160, 99999]) {
        final pick = pickClosestQuality(sources, h);
        expect(pick == null, sources.isEmpty, reason: why);
      }
    },
  );

  _fuzz<List<SubtitleTrack>>(
    'parseSubtitles',
    parseSubtitles,
    fixtures: [
      'subtitles_movie',
      'subtitles_episode',
      'subtitles_special',
      'video_info_special',
    ],
    invariants: (tracks, why) {
      final paths = <String>{};
      for (final t in tracks) {
        expect(isHttpUrl(t.url), isTrue, reason: why);
        final path = Uri.parse(t.url).path.toLowerCase();
        expect(paths.add(path), isTrue, reason: '$why: duplicate $path');
        expect(path.endsWith('.gif'), isFalse, reason: why);
        expect(t.languageCode, isNotEmpty, reason: why);
        if (t.isStyled) expect(t.languageCode, 'ar', reason: why);
      }
      final one = oneTrackPerLanguage(tracks);
      final plain = [
        for (final t in one)
          if (!t.isStyled) t.languageCode,
      ];
      expect(plain.toSet().length, plain.length, reason: why);
    },
  );

  _fuzz<List<Episode>>(
    'parseEpisodes',
    parseEpisodes,
    fixtures: [
      'series_episodes',
      'series_episodes_double',
      'series_episodes_finale',
    ],
    invariants: (episodes, why) {
      final ids = <String>{};
      for (var i = 0; i < episodes.length; i++) {
        final e = episodes[i];
        expect(ids.add(e.id), isTrue, reason: '$why: duplicate ${e.id}');
        expect(e.season, greaterThanOrEqualTo(1), reason: why);
        expect(e.episode, greaterThanOrEqualTo(1), reason: why);
        expect(e.numbering.numbers, isNotEmpty, reason: why);
        expect(_isHttpOrNull(e.imageUrl), isTrue, reason: why);
        if (i > 0) {
          final p = episodes[i - 1];
          expect(
            p.season < e.season ||
                (p.season == e.season && p.episode <= e.episode),
            isTrue,
            reason: '$why: not sorted',
          );
        }
      }
    },
  );

  _fuzz<List<int>>(
    'parseSeasons',
    parseSeasons,
    fixtures: ['series_seasons'],
    invariants: (seasons, why) {
      expect(
        seasons,
        [
          ...{...seasons},
        ]..sort(),
        reason: why,
      );
      for (final s in seasons) {
        expect(s, greaterThanOrEqualTo(1), reason: why);
      }
    },
  );

  _fuzz<SeekPreview?>(
    'parseSeekPreview',
    parseSeekPreview,
    fixtures: ['thumbnails', 'thumbnails_broken', 'thumbnails_none'],
    invariants: (preview, why) {
      if (preview == null) return;
      expect(preview.sheets.any((s) => s.rows > 0), isTrue, reason: why);
      for (final s in preview.sheets) {
        expect(s.rows, inInclusiveRange(0, SeekPreview.maxRows), reason: why);
        expect(isHttpUrl(s.url), isTrue, reason: why);
      }
      for (final seconds in [0, 5, 999, 1000, 54321]) {
        preview.frameAt(Duration(seconds: seconds));
      }
    },
  );

  _fuzz<List<Category>>(
    'parseCategories',
    parseCategories,
    fixtures: ['categories', 'main_categories_ar', 'sub_categories_en'],
    invariants: (cats, why) {
      expect({for (final c in cats) c.id}.length, cats.length, reason: why);
      for (final c in cats) {
        expect(c.name.isEmpty, isFalse, reason: why);
        expect(_isHttpOrNull(c.imageUrl), isTrue, reason: why);
      }
    },
  );

  _fuzz<List<CategoryLanguage>>(
    'parseCategoryLanguages',
    parseCategoryLanguages,
    fixtures: ['category_languages'],
    invariants: (langs, why) {
      final keys = {for (final l in langs) '${l.categoryId}/${l.languageId}'};
      expect(keys.length, langs.length, reason: why);
    },
  );

  _fuzz<List<FaqEntry>>(
    'parseFaq',
    parseFaq,
    fixtures: ['faq'],
    invariants: (faq, why) {
      for (var i = 1; i < faq.length; i++) {
        expect(faq[i - 1].order <= faq[i].order, isTrue, reason: why);
      }
    },
  );

  _fuzz<StaffPage?>(
    'parseStaffPage',
    parseStaffPage,
    fixtures: ['staff', 'staff_no_photo'],
    invariants: (page, why) {
      if (page == null) return;
      expect(page.name.trim(), isNotEmpty, reason: why);
      expect(_isHttpOrNull(page.imageUrl), isTrue, reason: why);
      _mediaItemInvariants(page.items, why);
    },
  );

  _fuzz(
    'parseCinemanaHealth',
    parseCinemanaHealth,
    fixtures: ['service_status'],
  );

  _fuzz(
    'parseIntroRanges',
    parseIntroRanges,
    invariants: (ranges, why) {
      for (final r in ranges) {
        expect(r.end > r.start, isTrue, reason: why);
      }
    },
  );

  test('merging and ranking search results keeps every title once', () {
    for (var seed = 0; seed < 400; seed++) {
      final g = _Gen(seed);
      final a = parseMediaItems(g.list(0));
      final b = parseMediaItems(g.list(0));
      final c = parseMediaItems(g.list(0));
      final merged = mergeSearchResults(a, b, c);
      expect(
        merged.map((i) => i.id).toSet(),
        {...a, ...b, ...c}.map((i) => i.id).toSet(),
        reason: 'seed $seed',
      );
      expect(merged.map((i) => i.id).toSet().length, merged.length);
      for (final q in ['', ' ', 'a', '(', r'\', '.*', 'friends', 'عربي']) {
        final ranked = rankSearchResults(q, merged);
        expect(ranked.length, merged.length, reason: 'seed $seed "$q"');
        expect(ranked.toSet(), merged.toSet(), reason: 'seed $seed "$q"');
      }
    }
  });
}

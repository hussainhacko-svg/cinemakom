import 'package:cinemakom/data/models/media_details.dart';
import 'package:cinemakom/data/parsers/details_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixture.dart';

void main() {
  group('media details', () {
    test('movie fixture', () {
      final d = parseMediaDetails(fixture('video_info_movie'))!;
      expect(d.item.id, isNotEmpty);
      expect(d.item.isSeries, isFalse);
      expect(d.actors, isNotEmpty);
      expect(d.actors.every((a) => a.role == StaffRole.actor), isTrue);
      expect(d.item.duration, isNotNull);
      expect(d.subtitles, isNotEmpty);
    });

    test('series root and later episode fixtures', () {
      final root = parseMediaDetails(fixture('video_info_series'))!;
      final ep = parseMediaDetails(fixture('video_info_episode'))!;
      expect(root.item.isSeries, isTrue);
      expect(root.item.rootSeriesId, isNull);
      expect(ep.item.isSeries, isTrue);
      expect(ep.item.seriesId, root.item.id);
    });

    test('extra fields', () {
      final d = parseMediaDetails({
        'nb': '1',
        'en_title': 'A',
        'videoLanguages': {'en_title': 'English', 'ar_title': 'الإنجليزية'},
        'trailer': 'https://www.youtube.com/watch?v=3jBWJIAfBOY&ab;_channel=X',
        'imdbUrlRef': '',
        'introSkipping': [
          {'start': '0', 'end': '27.12', 'control_level': '3'},
          {'start': '5', 'end': '5.2'},
        ],
        'skippingDurations': {
          'start': ['0'],
          'end': ['0.1'],
        },
        'videoCommentsNumber': 0,
        'videoLikesNumber': '10',
        'castable': 'true',
      })!;
      expect(d.audioLanguages.single.en, 'English');
      expect(d.trailerUrl, startsWith('https://'));
      expect(d.trailerYoutubeId, '3jBWJIAfBOY');
      expect(d.imdbUrl, isNull);
      expect(d.imdbUrlIsImdb, isFalse);
      expect(d.introRanges, [
        const SkipRange(Duration.zero, Duration(milliseconds: 27120)),
      ]);
      expect(d.castable, isTrue);
    });

    test('junk input', () {
      expect(parseMediaDetails(null), isNull);
      expect(parseMediaDetails([1, 2]), isNull);
      expect(parseMediaDetails({'en_title': 'no id'}), isNull);
    });
  });

  test('youtubeVideoId', () {
    expect(youtubeVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(
      youtubeVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(
      youtubeVideoId('https://www.imdb.com/video/imdb/vi199737113/'),
      isNull,
    );
    expect(youtubeVideoId(''), isNull);
  });

  test('external link: IMDb or MyAnimeList', () {
    MediaDetails d(String url) =>
        parseMediaDetails({'nb': '1', 'en_title': 'A', 'imdbUrlRef': url})!;
    expect(d('http://www.imdb.com/title/tt0111161/').imdbUrlIsImdb, isTrue);
    expect(d('https://myanimelist.net/anime/1').imdbUrlIsImdb, isFalse);
  });

  test('staff credits skip entries without ID or name', () {
    final credits = parseStaffCredits([
      {'nb': '1', 'name': 'A', 'staff_img': null},
      {'nb': '1', 'name': 'A dup'},
      {'name': 'no id'},
      {'nb': '2'},
    ], StaffRole.director);
    expect(credits.single.name, 'A');
    expect(credits.single.imageUrl, isNull);
    final placeholder = parseStaffCredits([
      {
        'nb': '3',
        'name': 'B',
        'staff_img': 'defaultImages/not_available.jpg',
        'staff_img_medium_thumb':
            'https://cnth2.shabakaty.com/defaultImages/not_available.jpg',
      },
    ], StaffRole.actor);
    expect(placeholder.single.imageUrl, isNull);
  });

  test('staff page fixture', () {
    final page = parseStaffPage(fixture('staff'))!;
    expect(page.name, isNotEmpty);
    expect(page.items, isNotEmpty);
    expect(parseStaffPage({'items': []}), isNull);
    expect(parseStaffPage(<Object?>[]), isNull);
  });

  test('staff page placeholder image is dropped', () {
    final page = parseStaffPage(fixture('staff_no_photo'))!;
    expect(page.imageUrl, isNull);
    expect(page.items, isNotEmpty);
  });

  test('faq fixture is sorted and bilingual', () {
    final faq = parseFaq(fixture('faq'));
    expect(faq, isNotEmpty);
    expect(
      faq.every((f) => f.question.en != null && f.question.ar != null),
      isTrue,
    );
    final orders = faq.map((f) => f.order).toList();
    expect(orders, [...orders]..sort());
  });
}

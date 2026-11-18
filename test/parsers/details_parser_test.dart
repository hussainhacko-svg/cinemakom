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
        'trailer': 'https://www.youtube.com/watch?v=x',
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
      expect(d.imdbUrl, isNull);
      expect(d.introRanges, [
        const SkipRange(Duration.zero, Duration(milliseconds: 27120)),
      ]);
      expect(d.parentalSkipRanges, isEmpty);
      expect(d.commentCount, 0);
      expect(d.likes, 10);
      expect(d.castable, isTrue);
    });

    test('junk input', () {
      expect(parseMediaDetails(null), isNull);
      expect(parseMediaDetails([1, 2]), isNull);
      expect(parseMediaDetails({'en_title': 'no id'}), isNull);
    });
  });

  test('parental skip ranges pair start/end and drop placeholders', () {
    expect(
      parseParentalSkipRanges(fixture('skip_durations')),
      isA<List<SkipRange>>(),
    );
    final ranges = parseParentalSkipRanges({
      'start': ['828.1', '42.2', '0', 'x'],
      'end': ['938.1', '43.0', '0.1'],
    });
    expect(ranges.map((r) => r.start.inSeconds), [42, 828]);
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
  });

  test('staff page fixture', () {
    final page = parseStaffPage(fixture('staff'))!;
    expect(page.name, isNotEmpty);
    expect(page.items, isNotEmpty);
    expect(parseStaffPage({'items': []}), isNull);
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

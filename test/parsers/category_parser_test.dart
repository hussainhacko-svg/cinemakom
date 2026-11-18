import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/parsers/category_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixture.dart';

void main() {
  test('category fixture has both languages', () {
    final cats = parseCategories(fixture('categories'));
    expect(cats, isNotEmpty);
    for (final c in cats) {
      expect(c.id, isNotEmpty);
      expect(c.name.en, isNotNull);
      expect(c.name.ar, isNotNull);
    }
  });

  test('mainCategories?lang=ar puts the plain title in Arabic', () {
    final cats = parseCategories(
      fixture('main_categories_ar'),
      lang: ApiLanguage.ar,
    );
    expect(cats, isNotEmpty);
    expect(cats.every((c) => c.name.ar != null && c.name.en == null), isTrue);
  });

  test('subCategories?lang=en puts the plain title in English', () {
    final cats = parseCategories(
      fixture('sub_categories_en'),
      lang: ApiLanguage.en,
    );
    expect(cats.every((c) => c.name.en != null), isTrue);
  });

  test('nested children, duplicates and bad entries', () {
    final cats = parseCategories({
      'nb': '1',
      'en_title': 'Parent',
      'subCategories': [
        {'nb': 2, 'title': 'Child'},
        {'nb': '1', 'title': 'Duplicate'},
        {'title': 'No id'},
        'garbage',
      ],
    });
    expect(cats.map((c) => c.id), ['1', '2']);
    expect(parseCategories(null), isEmpty);
  });

  test('category languages fixture', () {
    final langs = parseCategoryLanguages(fixture('category_languages'));
    expect(langs, isNotEmpty);
    for (final l in langs) {
      expect(l.categoryId, isNotEmpty);
      expect(l.languageId, isNotEmpty);
      expect(l.name.isEmpty, isFalse);
    }
  });

  test('category languages treat blank counts as 0', () {
    final langs = parseCategoryLanguages([
      {
        'nb': '149',
        'langArray': [
          {
            'catNb': '149',
            'langNb': '9',
            'lang_en_title': 'Arabic',
            'langFreq': '',
            'langFreqSeries': '2',
          },
        ],
      },
    ]);
    expect(langs.single.movieCount, 0);
    expect(langs.single.seriesCount, 2);
  });

  test('fallback genres are unique and named in both languages', () {
    expect(
      fallbackGenres.map((c) => c.id).toSet(),
      hasLength(fallbackGenres.length),
    );
    expect(
      fallbackGenres.every((c) => c.name.en != null && c.name.ar != null),
      isTrue,
    );
  });
}

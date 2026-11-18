import '../../core/json/json_utils.dart';
import '../../core/network/api_endpoints.dart';
import '../models/catalog_models.dart';
import '../models/localized_text.dart';

/// `category`, `mainCategories?lang=` and `subCategories?lang=`.
///
/// `mainCategories`/`subCategories` send `{nb, title}` with the title in the
/// requested [lang] (sorted by that title); `category` sends both `en_title`
/// and `ar_title`. `category` = the 15 main + 34 sub genres + `0`
/// ("uncategorized"); there is no parent/child structure.
/// Nested children are flattened. Entries without an ID or a name are skipped.
List<Category> parseCategories(Object? json, {ApiLanguage? lang}) {
  final out = <Category>[];
  final seen = <String>{};

  void visit(Object? node, int depth) {
    if (depth > 4) return;
    final map = asMap(node);
    if (map == null) return;
    try {
      final id = firstNonBlank(map, [
        'nb',
        'id',
        'categoryID',
        'cat_id',
        'subCategoryId',
        'category_id',
      ]);
      final plain = firstNonBlank(map, ['title', 'name', 'categoryTitle']);
      final en =
          firstNonBlank(map, ['en_title', 'title_en', 'en_name']) ??
          (lang == ApiLanguage.ar ? null : plain);
      final ar =
          firstNonBlank(map, ['ar_title', 'title_ar', 'ar_name']) ??
          (lang == ApiLanguage.ar ? plain : null);
      if (id != null && (en != null || ar != null) && seen.add(id)) {
        out.add(
          Category(
            id: id,
            name: LocalizedText(en: en, ar: ar),
            imageUrl: _image(map),
          ),
        );
      }
    } catch (_) {
      // Skip this entry, keep its children.
    }
    for (final key in const [
      'subCategories',
      'categories',
      'data',
      'items',
      'children',
      'list',
    ]) {
      for (final child in asList(map[key])) {
        visit(child, depth + 1);
      }
    }
  }

  for (final entry in json is List ? json : [json]) {
    visit(entry, 0);
  }
  return out;
}

/// `categoryLangFreqVideo`: categories, each with a `langArray` of
/// `{catNb, langNb, lang_en_title, lang_ar_title, langFreq, langFreqSeries}`.
List<CategoryLanguage> parseCategoryLanguages(Object? json) {
  final out = <CategoryLanguage>[];
  final seen = <String>{};
  for (final cat in asList(json)) {
    final catMap = asMap(cat);
    if (catMap == null) continue;
    final parentId = readString(catMap['nb']);
    for (final entry in asList(catMap['langArray'])) {
      try {
        final m = asMap(entry);
        if (m == null) continue;
        final categoryId = readString(m['catNb']) ?? parentId;
        final languageId = readString(m['langNb']);
        if (categoryId == null || languageId == null) continue;
        if (!seen.add('$categoryId/$languageId')) continue;
        final name = LocalizedText(
          en: readString(m['lang_en_title']),
          ar: readString(m['lang_ar_title']),
        );
        if (name.isEmpty) continue;
        out.add(
          CategoryLanguage(
            categoryId: categoryId,
            languageId: languageId,
            name: name,
            movieCount: parseIntLoose(m['langFreq']) ?? 0,
            seriesCount: parseIntLoose(m['langFreqSeries']) ?? 0,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }
  return out;
}

/// The main genres, used when the category endpoints fail.
///
/// IDs verified against `mainCategories` on 2026-11-19. (The Kotlin app's
/// fallback IDs 87–98 were wrong: 87 is "Supernatural", 91–96 don't exist.)
const List<Category> fallbackGenres = [
  Category(
    id: '84',
    name: LocalizedText(en: 'Action', ar: 'اكشن'),
  ),
  Category(
    id: '56',
    name: LocalizedText(en: 'Adventure', ar: 'مغامرة'),
  ),
  Category(
    id: '57',
    name: LocalizedText(en: 'Animation', ar: 'رسوم متحركة'),
  ),
  Category(
    id: '59',
    name: LocalizedText(en: 'Comedy', ar: 'كوميدي'),
  ),
  Category(
    id: '60',
    name: LocalizedText(en: 'Crime', ar: 'جريمة'),
  ),
  Category(
    id: '61',
    name: LocalizedText(en: 'Documentary', ar: 'وثائقي'),
  ),
  Category(
    id: '62',
    name: LocalizedText(en: 'Drama', ar: 'دراما'),
  ),
  Category(
    id: '67',
    name: LocalizedText(en: 'Fantasy', ar: 'خيالي'),
  ),
  Category(
    id: '70',
    name: LocalizedText(en: 'Horror', ar: 'رعب'),
  ),
  Category(
    id: '76',
    name: LocalizedText(en: 'Mystery', ar: 'غموض'),
  ),
  Category(
    id: '77',
    name: LocalizedText(en: 'Romance', ar: 'رومانسي'),
  ),
  Category(
    id: '78',
    name: LocalizedText(en: 'Sci-Fi', ar: 'خيال علمي'),
  ),
  Category(
    id: '79',
    name: LocalizedText(en: 'Sport', ar: 'رياضي'),
  ),
  Category(
    id: '80',
    name: LocalizedText(en: 'Thriller', ar: 'اثارة'),
  ),
  Category(
    id: '89',
    name: LocalizedText(en: 'Western', ar: 'حياة الغرب'),
  ),
];

/// Category images are almost always the `loading.gif` placeholder, which
/// is dropped.
String? _image(JsonMap map) {
  for (final key in ['imgMediumThumbObjUrl', 'imgObjUrl', 'imgThumbObjUrl']) {
    final url = realImageUrl(readString(map[key]));
    if (url != null) return url;
  }
  return null;
}

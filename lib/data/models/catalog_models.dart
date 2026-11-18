import 'localized_text.dart';
import 'media_item.dart';

/// A curated home row from `videoGroups`.
class VideoGroup {
  const VideoGroup({
    required this.id,
    required this.title,
    required this.items,
    this.hasPagination = false,
  });

  final String id;

  /// Already in the language the groups were requested in.
  final String title;
  final List<MediaItem> items;

  /// Whether `videoListPagination` can load more items for this group.
  final bool hasPagination;
}

/// One page of an offset-paged endpoint (`videosByCategory…`).
class OffsetPage {
  const OffsetPage({required this.items, this.nextOffset});

  final List<MediaItem> items;

  /// The `offset` to request next, or `null` at the end. The server keeps
  /// returning larger offsets past the end, so a short page ends paging.
  final int? nextOffset;

  bool get hasMore => nextOffset != null;
}

/// A genre or category.
class Category {
  const Category({required this.id, required this.name, this.imageUrl});

  final String id;
  final LocalizedText name;
  final String? imageUrl;

  @override
  String toString() => 'Category($id, ${name.en ?? name.ar})';
}

/// One (category, audio language) pair from `categoryLangFreqVideo`.
class CategoryLanguage {
  const CategoryLanguage({
    required this.categoryId,
    required this.languageId,
    required this.name,
    this.movieCount = 0,
    this.seriesCount = 0,
  });

  final String categoryId;

  /// Pass as `language_id` to `videosByCategoryAndLanguage`.
  final String languageId;
  final LocalizedText name;
  final int movieCount;
  final int seriesCount;
}

/// An FAQ entry from `faqQuestion`.
class FaqEntry {
  const FaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    this.category,
    this.order = 0,
  });

  final String id;
  final LocalizedText question;
  final LocalizedText answer;
  final String? category;
  final int order;
}

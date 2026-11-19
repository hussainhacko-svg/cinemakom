import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_endpoints.dart';
import '../models/media_item.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/search_repository.dart';

/// One loaded page of a [MediaSource].
class MediaPage {
  const MediaPage(this.items, {this.next});

  final List<MediaItem> items;

  /// The cursor of the next page, or `null` at the end.
  final int? next;
}

/// A list of titles that loads page by page: the source of every long list
/// (genre pages, "See all", search results) and of the Home rows, which show
/// a source's first page. Each API pages differently (page numbers, item
/// offsets, different end rules, docs/API.md §Paging); a source hides that
/// behind an opaque cursor.
///
/// Sources are values: two equal sources share one loaded list.
sealed class MediaSource {
  const MediaSource();

  /// The cursor of the first page.
  int get firstCursor => 0;

  Future<MediaPage> load(Ref ref, int cursor);

  /// Identifies the list; equal keys mean equal sources.
  Object get key;

  @override
  bool operator ==(Object other) =>
      other is MediaSource &&
      other.runtimeType == runtimeType &&
      other.key == key;

  @override
  int get hashCode => Object.hash(runtimeType, key);
}

/// Page-numbered lists that end on an empty page.
MediaPage _numbered(List<MediaItem> items, int page) =>
    MediaPage(items, next: items.isEmpty ? null : page + 1);

final class FeaturedSource extends MediaSource {
  const FeaturedSource();

  @override
  Object get key => 'featured';

  @override
  Future<MediaPage> load(Ref ref, int cursor) async => _numbered(
    await ref.read(catalogRepositoryProvider).featured(page: cursor),
    cursor,
  );
}

final class LatestSource extends MediaSource {
  const LatestSource(this.kind);

  final VideoKind kind;

  @override
  Object get key => kind;

  @override
  Future<MediaPage> load(Ref ref, int cursor) async {
    final repo = ref.read(catalogRepositoryProvider);
    return _numbered(
      kind == VideoKind.series
          ? await repo.latestSeries(page: cursor)
          : await repo.latestMovies(page: cursor),
      cursor,
    );
  }
}

/// Every movie or every series ("all genres"), sorted. Title sorts don't
/// work here ([SortOrder.worksOnCatalog]).
final class CatalogSource extends MediaSource {
  const CatalogSource(this.kind, this.sort);

  final VideoKind kind;
  final SortOrder sort;

  @override
  Object get key => (kind, sort);

  @override
  Future<MediaPage> load(Ref ref, int cursor) async => _numbered(
    await ref
        .read(catalogRepositoryProvider)
        .catalog(kind: kind, sort: sort, page: cursor),
    cursor,
  );
}

/// A curated video group's "See all" (`videoListPagination`). These end on
/// a short page.
final class GroupSource extends MediaSource {
  const GroupSource(this.groupId);

  final String groupId;

  static const pageSize = 12;

  @override
  Object get key => groupId;

  @override
  Future<MediaPage> load(Ref ref, int cursor) async {
    final items = await ref
        .read(catalogRepositoryProvider)
        .videoGroupPage(groupId, page: cursor);
    return MediaPage(items, next: items.length < pageSize ? null : cursor + 1);
  }
}

/// One genre, optionally limited to one audio language
/// (`videosByCategoryAndLanguage`). Offset-paged, 30 at a time, ending on a
/// short page.
final class GenreSource extends MediaSource {
  const GenreSource({
    required this.categoryId,
    this.kind = VideoKind.movies,
    this.sort = SortOrder.recentlyAdded,
    this.languageId,
  });

  final String categoryId;
  final VideoKind kind;
  final SortOrder sort;
  final String? languageId;

  @override
  Object get key => (categoryId, kind, sort, languageId);

  @override
  Future<MediaPage> load(Ref ref, int cursor) async {
    final repo = ref.read(catalogRepositoryProvider);
    final languageId = this.languageId;
    final page = languageId == null
        ? await repo.videosByCategory(
            categoryId: categoryId,
            kind: kind,
            sort: sort,
            offset: cursor,
          )
        : await repo.videosByCategoryAndLanguage(
            categoryId: categoryId,
            languageId: languageId,
            kind: kind,
            sort: sort,
            offset: cursor,
          );
    return MediaPage(
      page.items,
      next: page.hasMore ? cursor + ApiEndpoints.categoryPageSize : null,
    );
  }
}

/// Search results for [query] (title search plus AdvancedSearch, see
/// [SearchRepository.searchPage]).
final class SearchSource extends MediaSource {
  const SearchSource(this.query);

  final String query;

  @override
  Object get key => query.trim();

  @override
  Future<MediaPage> load(Ref ref, int cursor) async {
    final page = await ref
        .read(searchRepositoryProvider)
        .searchPage(query, page: cursor);
    return MediaPage(page.items, next: page.hasMore ? cursor + 1 : null);
  }
}

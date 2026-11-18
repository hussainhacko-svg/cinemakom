import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_providers.dart';
import '../models/media_item.dart';
import '../parsers/media_parser.dart';

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(apiClientProvider)),
);

class SearchRepository {
  SearchRepository(this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final DateTime Function() _clock;

  /// Title search: the base64 title search plus `AdvancedSearch` for movies
  /// and for series, run in parallel, merged, de-duplicated and ranked (exact
  /// match first). Like the website, `AdvancedSearch` gets the query as both
  /// title and staff name (OR-ed), so an actor's or director's name finds
  /// their titles too. Throws only when all three requests fail.
  Future<List<MediaItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final calls = [
      _api.fetch(ApiEndpoints.titleSearch(q)),
      _api.fetch(
        ApiEndpoints.advancedSearch(
          videoTitle: q,
          staffTitle: q,
          kind: VideoKind.series,
          now: _clock(),
        ),
      ),
      _api.fetch(
        ApiEndpoints.advancedSearch(
          videoTitle: q,
          staffTitle: q,
          kind: VideoKind.movies,
          now: _clock(),
        ),
      ),
    ];
    final errors = <ApiException>[];
    final results = await Future.wait(
      calls.map(
        (call) => call.then<Object?>(
          (v) => v,
          onError: (Object e) {
            if (e is! ApiException) throw e;
            errors.add(e);
            return null;
          },
        ),
      ),
    );
    if (errors.length == calls.length) throw errors.first;

    final byTitle = parseMediaItems(results[0]);
    final series = parseMediaItems(results[1], fallbackKind: VideoKind.series);
    final movies = parseMediaItems(results[2], fallbackKind: VideoKind.movies);
    return rankSearchResults(q, mergeSearchResults(byTitle, series, movies));
  }

  /// `AdvancedSearch` with filters, 12 per page. The year range defaults to
  /// 1900 → now. [kind] is required (the server returns only movies without
  /// it). Pages can be one item short mid-list: stop paging on an empty page.
  /// [categoryId] must be a real category ID (an unknown one is ignored).
  Future<List<MediaItem>> advancedSearch({
    required VideoKind kind,
    String? title,
    String? staffName,
    String? categoryId,
    int? yearFrom,
    int? yearTo,
    int page = 0,
  }) async => parseMediaItems(
    await _api.fetch(
      ApiEndpoints.advancedSearch(
        videoTitle: title,
        staffTitle: staffName,
        kind: kind,
        categoryId: categoryId,
        yearFrom: yearFrom,
        yearTo: yearTo,
        page: page,
        now: _clock(),
      ),
    ),
    fallbackKind: kind,
  );
}

/// Merges the three search sources in order (title search, series, movies).
/// Anything the series search returned is marked as a series. When an ID
/// repeats, the first copy wins unless it has no kind and a later one does.
List<MediaItem> mergeSearchResults(
  List<MediaItem> byTitle,
  List<MediaItem> series,
  List<MediaItem> movies,
) {
  final seriesIds = {for (final s in series) s.id};
  final merged = <String, MediaItem>{};
  for (final raw in [...byTitle, ...series, ...movies]) {
    final item = seriesIds.contains(raw.id) && raw.kind != VideoKind.series
        ? raw.copyWith(kind: VideoKind.series)
        : raw;
    final existing = merged[item.id];
    if (existing == null || (existing.kind == null && item.kind != null)) {
      merged[item.id] = item;
    }
  }
  return merged.values.toList();
}

/// Ranks like the Kotlin app: exact title, exact ignoring "(year)", starts
/// with, whole word, partial; ties go to the shorter title.
List<MediaItem> rankSearchResults(String query, List<MediaItem> items) {
  final q = query.trim().toLowerCase();
  final wholeWord = RegExp(
    '(^|[^\\p{L}\\p{N}])${RegExp.escape(q)}(\$|[^\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  int rank(MediaItem item) {
    final titles = [
      item.title.en,
      item.title.ar,
    ].whereType<String>().map((t) => t.trim().toLowerCase()).toList();
    if (titles.any((t) => t == q)) return 0;
    if (titles.any((t) => t.split('(').first.trim() == q)) return 1;
    if (titles.any((t) => t.startsWith(q))) return 2;
    if (titles.any(wholeWord.hasMatch)) return 3;
    return 4;
  }

  int length(MediaItem i) => (i.title.en ?? i.title.ar ?? '').length;
  final ranked = [for (final i in items) (rank(i), i)];
  // List.sort isn't stable, so break final ties by the original position.
  final position = {for (var k = 0; k < items.length; k++) items[k].id: k};
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) return byRank;
    final byLength = length(a.$2).compareTo(length(b.$2));
    if (byLength != 0) return byLength;
    return position[a.$2.id]!.compareTo(position[b.$2.id]!);
  });
  return [for (final r in ranked) r.$2];
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/catalog_providers.dart';
import '../../app/l10n/app_localizations.dart';
import '../../core/network/api_endpoints.dart';
import '../../data/models/catalog_models.dart';

/// How many audio-language choices a genre offers at most (the most common).
const genreLanguageLimit = 8;

/// The audio languages a genre has for a kind (`(categoryId, kind)`), most
/// titles first, at most [genreLanguageLimit]: the genre × language filter.
final genreLanguagesProvider = Provider.autoDispose
    .family<List<CategoryLanguage>, (String, VideoKind)>((ref, key) {
      final (categoryId, kind) = key;
      int count(CategoryLanguage l) =>
          kind == VideoKind.series ? l.seriesCount : l.movieCount;
      final all =
          ref.watch(categoryLanguagesProvider).value ??
          const <CategoryLanguage>[];
      return ([
            for (final l in all)
              if (l.categoryId == categoryId && count(l) > 0) l,
          ]..sort((a, b) => count(b).compareTo(count(a))))
          .take(genreLanguageLimit)
          .toList();
    });

String sortOrderLabel(AppLocalizations l10n, SortOrder s) => switch (s) {
  SortOrder.recentlyAdded => l10n.sortRecentlyAdded,
  SortOrder.oldestAdded => l10n.sortOldestAdded,
  SortOrder.newestRelease => l10n.sortNewestRelease,
  SortOrder.oldestRelease => l10n.sortOldestRelease,
  SortOrder.mostViewed => l10n.sortMostWatched,
  SortOrder.titleAscending => l10n.sortTitleAscending,
  SortOrder.titleDescending => l10n.sortTitleDescending,
};

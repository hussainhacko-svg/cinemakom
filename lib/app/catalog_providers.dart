import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_endpoints.dart';
import '../core/storage/preferences.dart';
import '../data/models/catalog_models.dart';
import '../data/repositories/catalog_repository.dart';

/// The language API lists with server-side names (groups, genres, staff)
/// are requested in: the UI language.
final apiLanguageProvider = Provider<ApiLanguage>(
  (ref) =>
      ref.watch(settingsProvider.select((s) => s.effectiveLanguage)) ==
          AppLanguage.arabic
      ? ApiLanguage.ar
      : ApiLanguage.en,
);

/// Every genre (main genres first), used by Home, Search, Details and the
/// genre pages. Kept for the session; it falls back to a built-in list when
/// the API fails ([CatalogRepository.genres]).
final genresProvider = FutureProvider<List<Category>>(
  (ref) => ref
      .read(catalogRepositoryProvider)
      .genres(ref.watch(apiLanguageProvider)),
);

/// Which audio languages each genre has, for the genre × language chips.
final categoryLanguagesProvider = FutureProvider<List<CategoryLanguage>>(
  (ref) => ref.read(catalogRepositoryProvider).categoryLanguages(),
);

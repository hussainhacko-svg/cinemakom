import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/catalog_providers.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/media_item.dart';
import '../../data/paging/paged_media.dart';
import '../../data/repositories/catalog_repository.dart';

/// The hero carousel: banners with wide covers.
final bannersProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final banners = await ref.read(catalogRepositoryProvider).banners();
  // A banner without its wide cover can't be shown in the hero.
  return [
    for (final b in banners)
      if (b.backdropUrl != null) b,
  ];
});

/// The curated rows, named in the UI language.
final videoGroupsProvider = FutureProvider.autoDispose<List<VideoGroup>>(
  (ref) => ref
      .read(catalogRepositoryProvider)
      .videoGroups(ref.watch(apiLanguageProvider)),
);

/// Pull to refresh: reloads every Home section.
void refreshHome(WidgetRef ref) {
  ref
    ..invalidate(bannersProvider)
    ..invalidate(videoGroupsProvider)
    ..invalidate(genresProvider)
    ..invalidate(pagedMediaProvider);
}

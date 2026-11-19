import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/repositories/media_repository.dart';

/// The full record of a title; `null` when the server has none.
final detailsProvider = FutureProvider.autoDispose
    .family<MediaDetails?, String>(
      (ref, id) => ref.read(mediaRepositoryProvider).details(id),
    );

/// Every episode of a series, by season then episode.
final episodesProvider = FutureProvider.autoDispose
    .family<List<Episode>, String>(
      (ref, seriesId) => ref.read(mediaRepositoryProvider).episodes(seriesId),
    );

/// "More like this" for the title [id].
final recommendationsProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, String>((ref, id) async {
      final details = await ref.watch(detailsProvider(id).future);
      if (details == null) return const [];
      return ref.read(mediaRepositoryProvider).recommendations(details.item);
    });

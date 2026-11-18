import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_providers.dart';
import '../models/media_details.dart';
import '../models/media_item.dart';
import '../models/playback_models.dart';
import '../parsers/details_parser.dart';
import '../parsers/media_parser.dart';
import '../parsers/playback_parser.dart';

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(ref.watch(apiClientProvider)),
);

/// Details, episodes, streams and everything else about one title.
class MediaRepository {
  MediaRepository(this._api);

  final ApiClient _api;

  /// `null` when the server has no usable record for [id].
  Future<MediaDetails?> details(String id) async =>
      parseMediaDetails(await _api.fetch(ApiEndpoints.videoInfo(id)));

  /// Every episode, sorted by season then episode. Pass [MediaItem.seriesId].
  Future<List<Episode>> episodes(String seriesId) async =>
      parseEpisodes(await _api.fetch(ApiEndpoints.seriesEpisodes(seriesId)));

  /// Season numbers only, for a season picker that loads quickly.
  Future<List<int>> seasons(String seriesId) async =>
      parseSeasons(await _api.fetch(ApiEndpoints.seriesSeasons(seriesId)));

  /// Stream qualities, highest first. For a series, pass an episode ID.
  Future<List<VideoSource>> streams(String id) async =>
      parseVideoSources(await _api.fetch(ApiEndpoints.streams(id)));

  /// Every subtitle file. Use [oneTrackPerLanguage] to pick one per language.
  Future<List<SubtitleTrack>> subtitles(String id) async =>
      parseSubtitles(await _api.fetch(ApiEndpoints.subtitles(id)));

  /// "More like this" from the recommendation service (what the website
  /// uses). Pass [MediaItem.seriesId] for a series. Falls back to the older
  /// `relatedVideos` endpoint when the service fails or returns nothing.
  Future<List<MediaItem>> recommendations(MediaItem item) async {
    try {
      final recs = parseMediaItems(
        await _api.fetch(
          ApiEndpoints.recommendations(item.seriesId, title: item.title.en),
        ),
      ).where((r) => r.id != item.seriesId).toList();
      if (recs.isNotEmpty) return recs;
    } on ApiException {
      // Fall through to relatedVideos.
    }
    return parseMediaItems(
      await _api.fetch(
        ApiEndpoints.related(item.seriesId, item.kind ?? VideoKind.movies),
      ),
      fallbackKind: item.kind,
    );
  }

  /// Seek-bar previews, or `null` when the title has none.
  Future<SeekPreview?> seekPreview(String id) async =>
      parseSeekPreview(await _api.fetch(ApiEndpoints.thumbnails(id)));

  /// Fresh metadata for many titles at once, e.g. to refresh favorites and
  /// history, in request order. Non-numeric IDs are dropped (one would empty
  /// the whole response), duplicates removed, and requests sent in chunks of
  /// [ApiEndpoints.maxIdsPerRequest]. Unknown IDs are simply missing.
  Future<List<MediaItem>> byIds(Iterable<String> ids) async {
    final valid = <String>{
      for (final raw in ids)
        if (_numericId.hasMatch(raw.trim())) raw.trim(),
    }.toList();
    final out = <MediaItem>[];
    for (var i = 0; i < valid.length; i += ApiEndpoints.maxIdsPerRequest) {
      final end = (i + ApiEndpoints.maxIdsPerRequest).clamp(0, valid.length);
      out.addAll(
        parseMediaItems(
          await _api.fetch(ApiEndpoints.videosByIds(valid.sublist(i, end))),
        ),
      );
    }
    return out;
  }

  static final _numericId = RegExp(r'^[1-9]\d*$');

  /// An actor or director page. `null` when the server has no such person.
  Future<StaffPage?> staff(String staffId, ApiLanguage lang) async =>
      parseStaffPage(await _api.fetch(ApiEndpoints.staff(staffId, lang)));
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
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

  /// `getVideosByIds` is sent in chunks of this size.
  static const int idsPerRequest = 50;

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

  /// "More like this".
  Future<List<MediaItem>> related(String id, VideoKind kind) async =>
      parseMediaItems(
        await _api.fetch(ApiEndpoints.related(id, kind)),
        fallbackKind: kind,
      );

  /// Scenes the parental filter skips (not intros: those are in
  /// [MediaDetails.introRanges]).
  Future<List<SkipRange>> parentalSkipRanges(String id) async =>
      parseParentalSkipRanges(await _api.fetch(ApiEndpoints.skipDurations(id)));

  /// Fresh metadata for many titles at once, e.g. to refresh favorites and
  /// history. Order follows the server's response.
  Future<List<MediaItem>> byIds(List<String> ids) async {
    final unique = ids.toSet().toList();
    final out = <MediaItem>[];
    for (var i = 0; i < unique.length; i += idsPerRequest) {
      final chunk = unique.sublist(
        i,
        (i + idsPerRequest).clamp(0, unique.length),
      );
      out.addAll(
        parseMediaItems(await _api.fetch(ApiEndpoints.videosByIds(chunk))),
      );
    }
    return out;
  }

  /// An actor or director page. `null` when the server has no such person.
  Future<StaffPage?> staff(String staffId, ApiLanguage lang) async =>
      parseStaffPage(await _api.fetch(ApiEndpoints.staff(staffId, lang)));
}

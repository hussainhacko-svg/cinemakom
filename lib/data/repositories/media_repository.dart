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
  MediaRepository(this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final DateTime Function() _clock;

  /// When stream URLs expire sooner than this, they are refetched past the
  /// API cache. Long enough for a whole film or most downloads.
  static const Duration minStreamValidity = Duration(hours: 6);

  /// `null` when the server has no usable record for [id].
  Future<MediaDetails?> details(String id) async =>
      parseMediaDetails(await _api.fetch(ApiEndpoints.videoInfo(id)));

  /// Every episode, sorted by season then episode. Pass [MediaItem.seriesId].
  Future<List<Episode>> episodes(String seriesId) async =>
      parseEpisodes(await _api.fetch(ApiEndpoints.seriesEpisodes(seriesId)));

  /// Season numbers only, for a season picker that loads quickly. Some
  /// series answer `[]` (or 400) although they have episodes; then the
  /// seasons are taken from the episode list.
  Future<List<int>> seasons(String seriesId) async {
    try {
      final seasons = parseSeasons(
        await _api.fetch(ApiEndpoints.seriesSeasons(seriesId)),
      );
      if (seasons.isNotEmpty) return seasons;
    } on ApiException catch (e) {
      if (e.kind != ApiErrorKind.http) rethrow;
    }
    return ({for (final e in await episodes(seriesId)) e.season}.toList())
      ..sort();
  }

  /// Stream qualities, highest first. For a series, pass an episode ID.
  ///
  /// A cache in front of the API sometimes serves signed URLs that have
  /// already expired (the CDN then answers 403). When any URL expires within
  /// [minStreamValidity], the list is refetched past that cache. The server
  /// itself reuses each file's signature until it expires (up to 7 days), so
  /// a URL can still expire sooner than the margin: when playback or a
  /// download gets a 403, call this again for a new URL. Call it right before
  /// playing or downloading; never store the URLs.
  ///
  /// [fresh] always skips the API cache. Use it after the CDN refused a URL
  /// that still claimed to be valid.
  Future<List<VideoSource>> streams(String id, {bool fresh = false}) async {
    final now = _clock().toUtc();
    if (!fresh) {
      final sources = parseVideoSources(
        await _api.fetch(ApiEndpoints.streams(id)),
      );
      if (sources.every((s) => s.isValidFor(minStreamValidity, now: now))) {
        return sources;
      }
    }
    return parseVideoSources(
      await _api.fetch(
        ApiEndpoints.streams(id, cacheBuster: '${now.millisecondsSinceEpoch}'),
      ),
    );
  }

  /// Every subtitle file, including styled ASS tracks. Use
  /// [oneTrackPerLanguage] to pick one plain track per language. Subtitle URLs
  /// stay valid for about 30 days.
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

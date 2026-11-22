import '../../core/network/api_client.dart';
import 'media_repository.dart';

// Fresh signed URLs for downloads the engine starts by itself: its own
// retries after a dropped connection, a task rescheduled after the app was
// killed, the next run after a system stop. A fresh URL from the API has at
// least 6 hours left (MediaRepository.streams), but on a slow connection a
// 27 GB file takes longer than that, and a retry with an expired URL gets
// 403s until the engine gives up (docs/DOWNLOADS.md §5.5, §12).
//
// background_downloader asks for a new URL through its `Auth` hook, in a
// background isolate on Android: no app state and no plugins, so this is
// pure Dart and builds its own ApiClient.

/// How long before its `Expires` a download URL is replaced. A run that has
/// started keeps going past it (the signature is checked once, when the
/// request arrives); only a new run needs a valid URL.
const downloadUrlRefreshMargin = Duration(hours: 1);

/// When a signed URL stops working, from its `Expires` query parameter
/// (seconds since the epoch), or `null` when it isn't signed.
DateTime? signedUrlExpiry(String url) {
  final raw = Uri.tryParse(url)?.queryParameters['Expires'];
  final seconds = raw == null ? null : int.tryParse(raw);
  return seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// A fresh URL for [videoId] in [quality] (a `VideoSource.label`), or
/// `null` when that quality is gone. Throws when the API can't be reached.
Future<String?> freshDownloadUrl(
  String videoId,
  String quality, {
  ApiClient? api,
}) async {
  final sources = await MediaRepository(
    api ?? ApiClient(),
  ).streams(videoId, fresh: true);
  return sources.where((s) => s.label == quality).firstOrNull?.url;
}

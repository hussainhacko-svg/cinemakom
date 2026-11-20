import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/downloads/downloader.dart';
import '../../core/platform/storage_space.dart';
import '../../core/storage/preferences.dart';
import '../../data/models/download.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/repositories/downloads_repository.dart';
import '../player/quality.dart';

// The download steps without any UI, shared by the phone and desktop
// sheets (download_actions.dart) and the TV panels (docs/TV.md §7.4). Each UI
// asks for the quality its own way, then queues the pick here.

/// [videoId]'s download, or `null` when it was never downloaded.
final downloadOfProvider = Provider.autoDispose.family<Download?, String>((
  ref,
  videoId,
) {
  final all = ref.watch(downloadsProvider).value ?? const <Download>[];
  return all.where((d) => d.videoId == videoId).firstOrNull;
});

/// [videoId]'s live progress while it runs.
final progressOfProvider = Provider.autoDispose
    .family<DownloadProgress?, String>(
      (ref, videoId) => ref.watch(downloadProgressProvider).value?[videoId],
    );

/// Reads the free bytes where downloads go, or `null` where that can't be
/// read (only Android can; docs/TV.md §7.4). Tests override it.
final downloadFreeSpaceProvider = Provider<Future<int?> Function()>(
  (ref) => () async {
    final root = await ref.read(downloadRootProvider)();
    return freeBytes(root.directory);
  },
);

/// Whether a download of [bytes] fits in [free] and still leaves the
/// engine's reserve. Unknown sizes and unknown free space count as fitting:
/// the engine still stops at its reserve.
bool downloadFits(int? bytes, int? free) =>
    bytes == null ||
    free == null ||
    bytes + downloadSpaceReserveMb * 1024 * 1024 <= free;

/// "2.9 GB", "640 MB".
String formatBytes(AppLocalizations l10n, int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) {
    final value = bytes / gb;
    return l10n.sizeGb(value.toStringAsFixed(value >= 10 ? 0 : 1));
  }
  return l10n.sizeMb((bytes / mb).clamp(1, 1023).toStringAsFixed(0));
}

String problemText(AppLocalizations l10n, DownloadProblem? problem) =>
    switch (problem) {
      DownloadProblem.network => l10n.downloadProblemNetwork,
      DownloadProblem.noSpace => l10n.downloadProblemSpace,
      DownloadProblem.unavailable => l10n.downloadProblemUnavailable,
      DownloadProblem.storage => l10n.downloadProblemStorage,
      DownloadProblem.unknown || null => l10n.downloadProblemUnknown,
    };

/// The qualities [videoId] can be downloaded in, with their sizes, and the
/// one to preselect (the Settings quality, else the nearest one).
class DownloadOffer {
  const DownloadOffer(this.choices, this.preferred);

  final List<DownloadChoice> choices;
  final DownloadChoice preferred;
}

/// What a download of [videoId] can be: `null` when there's nothing to
/// download. Throws when the request fails (show it with `errorMessage`).
/// For a season, pass its first episode: the others are about the same size.
Future<DownloadOffer?> downloadOffer(WidgetRef ref, String videoId) async {
  final height = ref.read(settingsProvider).defaultQuality.height;
  final choices = await ref.read(downloadsRepositoryProvider).choices(videoId);
  if (choices.isEmpty) return null;
  final preferred = pickQuality([for (final c in choices) c.source], height);
  return DownloadOffer(
    choices,
    choices.firstWhere((c) => c.source == preferred),
  );
}

/// Queues [item], or its [episode], in the [picked] quality. Throws when it
/// can't be queued.
Future<void> queueDownload(
  WidgetRef ref,
  MediaItem item,
  DownloadChoice picked, {
  Episode? episode,
}) => ref
    .read(downloadsRepositoryProvider)
    .download(
      item,
      episode: episode,
      source: picked.source,
      bytes: picked.bytes,
    );

/// Queues every episode of [season] that isn't on the device yet, in the
/// [picked] quality. Returns how many were queued.
Future<int> queueSeason(
  WidgetRef ref,
  MediaItem series,
  List<Episode> season,
  DownloadChoice picked,
) => ref
    .read(downloadsRepositoryProvider)
    .downloadEpisodes(
      series,
      season,
      picked.source.height ?? ref.read(settingsProvider).defaultQuality.height,
    );

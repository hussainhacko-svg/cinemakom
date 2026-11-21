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

/// Whether [videoId] is a finished download whose file was removed outside
/// the app (docs/DOWNLOADS.md §5.8).
final isDownloadMissingProvider = Provider.autoDispose.family<bool, String>(
  (ref, videoId) =>
      ref.watch(downloadMissingProvider).value?.contains(videoId) ?? false,
);

/// Builds localized [DownloadNotices] for both global and per-task system
/// notifications (docs/DOWNLOADS.md §5.9).
DownloadNotices buildDownloadNotices(AppLocalizations l10n) => DownloadNotices(
  running: l10n.noticeDownloading,
  complete: l10n.noticeDownloaded,
  failed: l10n.noticeFailed,
  paused: l10n.noticePaused,
  waiting: l10n.noticeWaitingSlot,
  formatSize: (bytes) => formatBytes(l10n, bytes),
  downloadedFolder: l10n.noticeDownloadedFolder,
  downloadedSize: l10n.noticeDownloadedSize,
);

/// Reads the free bytes where downloads go, or `null` where that can't be
/// read (only Android can; docs/TV.md §7.4). Tests override it.
final downloadFreeSpaceProvider = Provider<Future<int?> Function()>(
  (ref) => () async {
    final root = await ref.read(downloadRootProvider)();
    return freeBytes(root.directory);
  },
);

/// Free space and engine temp-file bytes, refreshed whenever downloads change.
final downloadStorageInfoProvider =
    FutureProvider.autoDispose<({int? freeBytes, int tempBytes})>((ref) async {
      ref.watch(downloadsProvider);
      final free = await ref.read(downloadFreeSpaceProvider)();
      final temp = await ref.read(downloadsRepositoryProvider).tempBytes();
      return (freeBytes: free, tempBytes: temp);
    });

/// Bytes required to finish a download of [bytes] (accounting for already
/// saved [downloadedBytes], the engine reserve, and an optional copy at finish
/// — Rule 10, docs/DOWNLOADS.md §5.1).
int downloadRequiredBytes(
  int bytes, {
  int downloadedBytes = 0,
  bool needsCopy = false,
}) {
  final remaining = (bytes - downloadedBytes).clamp(0, bytes);
  return remaining +
      downloadSpaceReserveMb * 1024 * 1024 +
      (needsCopy ? bytes : 0);
}

/// How many additional bytes are needed when a download does not fit in [free],
/// or `0` when it fits (or when size / free space is unknown).
int downloadSpaceDeficit(
  int? bytes,
  int? free, {
  int downloadedBytes = 0,
  bool needsCopy = false,
}) {
  if (bytes == null || free == null) return 0;
  final needed = downloadRequiredBytes(
    bytes,
    downloadedBytes: downloadedBytes,
    needsCopy: needsCopy,
  );
  return needed > free ? needed - free : 0;
}

/// Whether a download of [bytes] fits in [free] and still leaves the
/// engine's reserve (plus a copy if [needsCopy]). Unknown sizes and unknown
/// free space count as fitting: the engine still stops at its reserve.
bool downloadFits(
  int? bytes,
  int? free, {
  int downloadedBytes = 0,
  bool needsCopy = false,
}) =>
    downloadSpaceDeficit(
      bytes,
      free,
      downloadedBytes: downloadedBytes,
      needsCopy: needsCopy,
    ) ==
    0;

/// "2.9 GB", "640 MB", "0 MB". Never rounds 0 up to "1 MB" (DOWNLOADS.md §3.2).
String formatBytes(AppLocalizations l10n, int bytes) {
  if (bytes <= 0) return l10n.sizeMb('0');
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) {
    final value = bytes / gb;
    return l10n.sizeGb(value.toStringAsFixed(value >= 10 ? 0 : 1));
  }
  return l10n.sizeMb((bytes / mb).clamp(1, 1023).toStringAsFixed(0));
}

/// Total bytes of [d], preferring live progress when known.
int? downloadTotalBytes(Download d, DownloadProgress? progress) =>
    progress?.expectedBytes ?? d.totalBytes;

/// Downloaded bytes of [d], falling back to the persisted row value when
/// paused, failed, or idle (never drops to 0: DOWNLOADS.md §5.3).
int downloadDoneBytes(Download d, DownloadProgress? progress) {
  if (d.status == DownloadStatus.complete) {
    return d.totalBytes ?? d.downloadedBytes;
  }
  final total = downloadTotalBytes(d, progress);
  if (progress != null && total != null && total > 0) {
    return (total * progress.fraction).round().clamp(0, total);
  }
  return d.downloadedBytes;
}

/// 0–1 progress fraction for [d], using live progress when running and saved
/// bytes otherwise (DOWNLOADS.md §5.10).
double downloadFraction(Download d, DownloadProgress? progress) {
  if (d.status == DownloadStatus.complete) return 1;
  if (progress != null) return progress.fraction.clamp(0.0, 1.0);
  return d.savedFraction;
}

/// "3.6 GB of 27 GB" when bytes are saved and total is known, or "3.6 GB"
/// when total is unknown. Returns `null` when nothing has been saved yet so
/// "1 MB of 27 GB" can never appear.
String? downloadSizesLabel(
  AppLocalizations l10n,
  Download d,
  DownloadProgress? progress,
) {
  final done = downloadDoneBytes(d, progress);
  final total = downloadTotalBytes(d, progress);
  if (done <= 0) {
    return total != null && d.status == DownloadStatus.running
        ? l10n.downloadOf(formatBytes(l10n, 0), formatBytes(l10n, total))
        : null;
  }
  if (total == null) return formatBytes(l10n, done);
  return l10n.downloadOf(formatBytes(l10n, done), formatBytes(l10n, total));
}

/// Bytes used by finished downloads plus saved partial bytes of active ones.
int downloadUsedBytes(
  List<Download> all,
  Map<String, DownloadProgress> progress,
) {
  var used = 0;
  for (final d in all) {
    used += downloadDoneBytes(d, progress[d.videoId]);
  }
  return used;
}

String problemText(AppLocalizations l10n, DownloadProblem? problem) =>
    switch (problem) {
      DownloadProblem.network => l10n.downloadProblemNetwork,
      DownloadProblem.linkExpired => l10n.downloadProblemLinkExpired,
      DownloadProblem.noSpace => l10n.downloadProblemSpace,
      DownloadProblem.unavailable => l10n.downloadProblemUnavailable,
      DownloadProblem.storage => l10n.downloadProblemStorage,
      DownloadProblem.interrupted => l10n.downloadProblemInterrupted,
      DownloadProblem.server => l10n.downloadProblemServer,
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

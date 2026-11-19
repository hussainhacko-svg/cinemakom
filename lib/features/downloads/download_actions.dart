import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/choice_picker.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/media_text.dart';
import '../../core/storage/preferences.dart';
import '../../data/models/download.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/repositories/downloads_repository.dart';
import '../player/quality.dart';

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

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for a quality (with file sizes, the Settings quality preselected)
/// and downloads [item], or its [episode]. Returns when it is queued.
Future<void> startDownload(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  Episode? episode,
}) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  final height = ref.read(settingsProvider).defaultQuality.height;
  final List<DownloadChoice> choices;
  try {
    choices = await repo.choices(episode?.id ?? item.id);
  } on Object catch (e) {
    if (context.mounted) _say(context, errorMessage(l10n, e));
    return;
  }
  if (!context.mounted) return;
  if (choices.isEmpty) {
    _say(context, l10n.downloadProblemUnavailable);
    return;
  }
  final preferred = pickQuality([for (final c in choices) c.source], height);
  final picked = await showChoicePicker<DownloadChoice>(
    context,
    title: l10n.downloadQualityTitle,
    selected: choices.firstWhere((c) => c.source == preferred),
    choices: [
      for (final c in choices)
        Choice(
          c,
          c.bytes == null
              ? qualityChipLabel(c.source)
              : l10n.downloadChoice(
                  context.isolate(qualityChipLabel(c.source)),
                  context.isolate(formatBytes(l10n, c.bytes!)),
                ),
        ),
    ],
  );
  if (picked == null || !context.mounted) return;
  try {
    await repo.download(
      item,
      episode: episode,
      source: picked.source,
      bytes: picked.bytes,
    );
    if (context.mounted) _say(context, l10n.downloadAdded);
  } on Object {
    if (context.mounted) _say(context, l10n.downloadStartFailed);
  }
}

/// Downloads every episode of [season] that isn't on the device yet, in a
/// quality picked once (sizes from its first episode).
Future<void> startSeasonDownload(
  BuildContext context,
  WidgetRef ref,
  MediaItem series,
  List<Episode> season,
) async {
  if (season.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  final height = ref.read(settingsProvider).defaultQuality.height;
  final List<DownloadChoice> choices;
  try {
    choices = await repo.choices(season.first.id);
  } on Object catch (e) {
    if (context.mounted) _say(context, errorMessage(l10n, e));
    return;
  }
  if (!context.mounted || choices.isEmpty) return;
  final preferred = pickQuality([for (final c in choices) c.source], height);
  final picked = await showChoicePicker<DownloadChoice>(
    context,
    title: l10n.downloadQualityTitle,
    selected: choices.firstWhere((c) => c.source == preferred),
    choices: [
      for (final c in choices)
        Choice(
          c,
          c.bytes == null
              ? qualityChipLabel(c.source)
              : l10n.downloadChoiceEach(
                  context.isolate(qualityChipLabel(c.source)),
                  context.isolate(formatBytes(l10n, c.bytes!)),
                ),
        ),
    ],
  );
  if (picked == null || !context.mounted) return;
  final queued = await repo.downloadEpisodes(
    series,
    season,
    picked.source.height ?? height,
  );
  if (context.mounted) _say(context, l10n.downloadSeasonQueued(queued));
}

enum _Action { play, pause, resume, cancel, delete }

/// What can be done with [d]: play or delete a finished one; pause,
/// resume or try again, and cancel an unfinished one.
Future<void> showDownloadMenu(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  final action = await showChoicePicker<_Action?>(
    context,
    title: d.isEpisode
        ? '${context.titleOf(d.item)} · '
              '${l10n.seasonEpisodeShort(d.season!, d.episode!)}'
        : context.titleOf(d.item),
    selected: null,
    choices: [
      if (d.status == DownloadStatus.complete) ...[
        Choice(_Action.play, l10n.play),
        Choice(_Action.delete, l10n.downloadDelete),
      ] else ...[
        if (d.status == DownloadStatus.running ||
            d.status == DownloadStatus.queued)
          Choice(_Action.pause, l10n.downloadPause)
        else
          Choice(
            _Action.resume,
            d.status == DownloadStatus.failed
                ? l10n.retry
                : l10n.downloadResume,
          ),
        Choice(_Action.cancel, l10n.downloadCancel),
      ],
    ],
  );
  if (!context.mounted) return;
  switch (action) {
    case _Action.play:
      openPlayer(context, d.request);
    case _Action.pause:
      await repo.pause(d.videoId);
    case _Action.resume:
      await repo.resume(d.videoId);
    case _Action.cancel:
    case _Action.delete:
      await repo.delete(d.videoId);
    case null:
      break;
  }
}

/// A determinate ring for a running download (not a loading spinner:
/// DESIGN.md §4 keeps those out), with [child] in the middle.
class DownloadRing extends StatelessWidget {
  const DownloadRing({
    super.key,
    required this.fraction,
    required this.child,
    this.size = 22,
  });

  final double fraction;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CircularProgressIndicator(
            value: fraction.clamp(0.02, 1),
            strokeWidth: 2,
            color: MarqueeColors.bulb,
            backgroundColor: MarqueeColors.velvet,
          ),
        ),
        child,
      ],
    ),
  );
}

/// The icon a download shows in its state.
Widget downloadIcon(
  Download? d,
  DownloadProgress? progress, {
  double size = 20,
}) => switch (d?.status) {
  null => Icon(Icons.download_rounded, size: size),
  DownloadStatus.complete => Icon(
    Icons.download_done_rounded,
    size: size,
    color: MarqueeColors.bulb,
  ),
  DownloadStatus.failed => Icon(
    Icons.error_outline_rounded,
    size: size,
    color: MarqueeColors.ember,
  ),
  DownloadStatus.paused => Icon(Icons.pause_rounded, size: size),
  DownloadStatus.queued || DownloadStatus.running => DownloadRing(
    fraction: progress?.fraction ?? 0,
    size: size + 2,
    child: Icon(Icons.arrow_downward_rounded, size: size * 0.6),
  ),
};

/// Details' Download button for a movie (DESIGN.md §8 secondary pill):
/// "Download", then its progress, then "Downloaded". A started one opens
/// [showDownloadMenu].
class DownloadPill extends ConsumerWidget {
  const DownloadPill({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final d = ref.watch(downloadOfProvider(item.id));
    final progress = ref.watch(progressOfProvider(item.id));
    final label = switch (d?.status) {
      null => l10n.download,
      DownloadStatus.complete => l10n.downloaded,
      DownloadStatus.paused => l10n.downloadPaused,
      DownloadStatus.failed => problemText(l10n, d!.problem),
      DownloadStatus.queued => l10n.downloadQueued,
      DownloadStatus.running =>
        progress == null
            ? l10n.downloadingStatus
            : '${l10n.downloadingStatus} · ${(progress.fraction * 100).floor()}%',
    };
    return OutlinedButton.icon(
      onPressed: () => d == null
          ? startDownload(context, ref, item)
          : showDownloadMenu(context, ref, d),
      icon: downloadIcon(d, progress, size: 18),
      label: Text(label),
    );
  }
}

/// An episode row's download button (40 px): the state's icon; a tap
/// downloads, or opens [showDownloadMenu].
class EpisodeDownloadButton extends ConsumerWidget {
  const EpisodeDownloadButton({
    super.key,
    required this.series,
    required this.episode,
  });

  final MediaItem series;
  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final d = ref.watch(downloadOfProvider(episode.id));
    final progress = ref.watch(progressOfProvider(episode.id));
    return IconButton(
      tooltip: d == null
          ? l10n.downloadEpisode
          : d.status == DownloadStatus.complete
          ? l10n.downloaded
          : d.status == DownloadStatus.failed
          ? problemText(l10n, d.problem)
          : l10n.downloadingStatus,
      onPressed: () => d == null
          ? startDownload(context, ref, series, episode: episode)
          : showDownloadMenu(context, ref, d),
      style: IconButton.styleFrom(fixedSize: const Size.square(40)),
      icon: downloadIcon(d, progress),
    );
  }
}

/// Details' "Download season" (a secondary pill above the episode rows).
class SeasonDownloadButton extends ConsumerWidget {
  const SeasonDownloadButton({
    super.key,
    required this.series,
    required this.season,
  });

  final MediaItem series;
  final List<Episode> season;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
    onPressed: () => startSeasonDownload(context, ref, series, season),
    icon: const Icon(Icons.download_rounded, size: 18),
    label: Text(AppLocalizations.of(context).downloadSeason),
  );
}

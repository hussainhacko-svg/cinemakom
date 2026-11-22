import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/choice_picker.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/media_text.dart';
import '../../core/platform/platform_info.dart';
import '../../data/models/download.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/repositories/downloads_repository.dart';
import '../player/quality.dart';
import 'download_flow.dart';

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
  final DownloadOffer? offer;
  try {
    offer = await downloadOffer(ref, episode?.id ?? item.id);
  } on Object catch (e) {
    if (context.mounted) _say(context, errorMessage(l10n, e));
    return;
  }
  if (!context.mounted) return;
  if (offer == null) {
    _say(context, l10n.downloadProblemUnavailable);
    return;
  }
  final picked = await showChoicePicker<DownloadChoice>(
    context,
    title: l10n.downloadQualityTitle,
    selected: offer.preferred,
    choices: [
      for (final c in offer.choices)
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
  final free = await ref.read(downloadFreeSpaceProvider)();
  if (!context.mounted) return;
  final deficit = downloadSpaceDeficit(picked.bytes, free);
  if (deficit > 0) {
    _say(context, l10n.downloadSpaceNeeded(formatBytes(l10n, deficit)));
    return;
  }
  try {
    await queueDownload(ref, item, picked, episode: episode);
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
  final DownloadOffer? offer;
  try {
    offer = await downloadOffer(ref, season.first.id);
  } on Object catch (e) {
    if (context.mounted) _say(context, errorMessage(l10n, e));
    return;
  }
  if (!context.mounted || offer == null) return;
  final picked = await showChoicePicker<DownloadChoice>(
    context,
    title: l10n.downloadQualityTitle,
    selected: offer.preferred,
    choices: [
      for (final c in offer.choices)
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
  // Rule 10 for the whole season: every episode still to download, at about
  // the first one's size.
  final count = seasonEpisodesToQueue(ref, season);
  final free = await ref.read(downloadFreeSpaceProvider)();
  if (!context.mounted) return;
  final deficit = downloadSpaceDeficit(
    picked.bytes == null ? null : picked.bytes! * count,
    free,
  );
  if (deficit > 0) {
    _say(context, l10n.downloadSpaceNeeded(formatBytes(l10n, deficit)));
    return;
  }
  final queued = await queueSeason(ref, series, season, picked);
  if (context.mounted) _say(context, l10n.downloadSeasonQueued(queued));
}

enum _Action {
  play,
  redownload,
  pause,
  resume,
  showInFolder,
  details,
  cancel,
  delete,
  remove,
}

/// Opens the folder containing [filePath] in the desktop file manager
/// (docs/DOWNLOADS.md §5.6, §5.10).
Future<void> showInFolder(String filePath) async {
  try {
    await launchUrl(Uri.directory(p.dirname(filePath)));
  } on Object {
    // Best effort on desktop.
  }
}

/// What can be done with [d]: play, show in folder (desktop), details or
/// delete a finished one; Download again or Remove when its file was removed
/// outside the app; pause, resume or try again, details, and cancel an
/// unfinished one.
Future<void> showDownloadMenu(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  final missing = ref.read(isDownloadMissingProvider(d.videoId));
  final action = await showChoicePicker<_Action?>(
    context,
    title: d.isEpisode
        ? context.joinMeta([
            context.titleOf(d.item),
            l10n.seasonEpisodeShort(d.season!, d.episode!),
          ])
        : context.titleOf(d.item),
    selected: null,
    choices: [
      if (d.status == DownloadStatus.complete && missing) ...[
        Choice(_Action.redownload, l10n.downloadAgain),
        Choice(_Action.details, l10n.downloadDetails),
        Choice(_Action.remove, l10n.downloadRemove),
      ] else if (d.status == DownloadStatus.complete) ...[
        Choice(_Action.play, l10n.play),
        if (isDesktop) Choice(_Action.showInFolder, l10n.downloadShowInFolder),
        Choice(_Action.details, l10n.downloadDetails),
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
        Choice(_Action.details, l10n.downloadDetails),
        Choice(_Action.cancel, l10n.downloadCancel),
      ],
    ],
  );
  if (!context.mounted) return;
  switch (action) {
    case _Action.play:
      openPlayer(context, d.request);
    case _Action.redownload:
      await redownloadMissing(context, ref, d);
    case _Action.pause:
      await repo.pause(d.videoId);
    case _Action.resume:
      await resumeDownload(context, ref, d);
    case _Action.showInFolder:
      await showInFolder(await repo.filePath(d));
    case _Action.details:
      await showDownloadDetails(context, ref, d);
    case _Action.cancel:
    case _Action.remove:
      await repo.delete(d.videoId);
    case _Action.delete:
      final sure = await showChoicePicker<bool>(
        context,
        title: l10n.downloadDeleteConfirm,
        selected: false,
        choices: [Choice(true, l10n.downloadDelete)],
      );
      if (sure == true) await repo.delete(d.videoId);
    case null:
      break;
  }
}

/// Resumes or retries [d], when the rest of it fits (rule 10). If the
/// stored quality is no longer offered by the server, asks the user before
/// switching quality and starting over (docs/DOWNLOADS.md §5.5).
Future<void> resumeDownload(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  if (!await _fits(context, ref, d)) return;
  final outcome = await repo.resume(d.videoId);
  if (!context.mounted) return;
  switch (outcome) {
    case ResumeQualityGone(:final previousQuality, :final fallback):
      if (await _confirmSwitch(context, ref, d, previousQuality, fallback) &&
          context.mounted) {
        await repo.resume(d.videoId, switchTo: fallback);
      }
    case ResumeStarted(startedOver: true):
      _say(context, l10n.downloadStartedOver);
    case ResumeStarted() || ResumeFailed():
      break;
  }
}

/// Downloads again a finished download whose file was removed outside the
/// app (§5.8), asking first when its quality is gone. Until it starts, the
/// row stays as it was.
Future<void> redownloadMissing(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  if (!await _fits(context, ref, d)) return;
  final outcome = await repo.redownload(d.videoId);
  if (!context.mounted) return;
  switch (outcome) {
    case ResumeQualityGone(:final previousQuality, :final fallback):
      if (await _confirmSwitch(context, ref, d, previousQuality, fallback) &&
          context.mounted) {
        await repo.redownload(d.videoId, switchTo: fallback);
      }
    case ResumeFailed(:final problem?):
      _say(context, problemText(l10n, problem));
    case ResumeStarted() || ResumeFailed():
      break;
  }
}

/// Whether what [d] still needs fits on the disk (another quality's
/// [bytes] when given); says how much is missing when it doesn't.
Future<bool> _fits(
  BuildContext context,
  WidgetRef ref,
  Download d, {
  int? bytes,
}) async {
  final deficit = await downloadSpaceShortfall(ref, d, bytes: bytes);
  if (deficit <= 0) return true;
  if (context.mounted) {
    final l10n = AppLocalizations.of(context);
    _say(context, l10n.downloadSpaceNeeded(formatBytes(l10n, deficit)));
  }
  return false;
}

/// Asks before switching [d] to [fallback] (starting over), and checks the
/// new quality fits.
Future<bool> _confirmSwitch(
  BuildContext context,
  WidgetRef ref,
  Download d,
  String previousQuality,
  VideoSource fallback,
) async {
  final l10n = AppLocalizations.of(context);
  final sure = await showChoicePicker<bool>(
    context,
    title: l10n.downloadQualityGoneTitle(previousQuality),
    selected: false,
    choices: [
      Choice(true, l10n.downloadSwitchQuality(qualityChipLabel(fallback))),
    ],
  );
  if (sure != true || !context.mounted) return false;
  final bytes = await ref.read(downloadsRepositoryProvider).sizeOf(fallback);
  if (!context.mounted) return false;
  return _fits(context, ref, d, bytes: bytes);
}

/// Shows a download's reason, engine message, saved progress and file path
/// (docs/DOWNLOADS.md §5.10).
Future<void> showDownloadDetails(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final text = MarqueeText.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  final progress = ref.read(progressOfProvider(d.videoId));
  final path = await repo.filePath(d);
  if (!context.mounted) return;
  final sizes = downloadSizesLabel(l10n, d, progress);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: MarqueeColors.booth,
      title: Text(l10n.downloadDetails, style: text.title),
      // Long engine messages and paths scroll rather than overflow.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.status == DownloadStatus.failed) ...[
              Text(l10n.downloadDetailReason, style: text.caption),
              const SizedBox(height: 2),
              Text(
                problemText(l10n, d.problem),
                style: text.body.copyWith(color: MarqueeColors.ember),
              ),
              const SizedBox(height: MarqueeSpace.m),
            ],
            if (d.problemDetail case final detail? when detail.isNotEmpty) ...[
              Text(l10n.downloadDetailEngine, style: text.caption),
              const SizedBox(height: 2),
              Text(detail, style: text.caption),
              const SizedBox(height: MarqueeSpace.m),
            ],
            if (sizes != null) ...[
              Text(l10n.downloadDetailProgress, style: text.caption),
              const SizedBox(height: 2),
              Text(sizes, style: text.body),
              const SizedBox(height: MarqueeSpace.m),
            ],
            Text(l10n.downloadDetailPath, style: text.caption),
            const SizedBox(height: 2),
            SelectableText(path, style: text.caption),
          ],
        ),
      ),
      actions: [
        if (isDesktop && d.status == DownloadStatus.complete)
          TextButton(
            onPressed: () => showInFolder(path),
            child: Text(l10n.downloadShowInFolder),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.downloadClose),
        ),
      ],
    ),
  );
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
  bool missing = false,
}) => switch (d?.status) {
  null => Icon(Icons.download_rounded, size: size),
  DownloadStatus.complete when missing => Icon(
    Icons.error_outline_rounded,
    size: size,
    color: MarqueeColors.ember,
  ),
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
    fraction: downloadFraction(d!, progress),
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
    final missing = ref.watch(isDownloadMissingProvider(item.id));
    final label = switch (d?.status) {
      null => l10n.download,
      DownloadStatus.complete when missing => l10n.downloadFileRemoved,
      DownloadStatus.complete => l10n.downloaded,
      DownloadStatus.paused =>
        d!.isWaitingForConnection
            ? l10n.downloadWaitingConnection
            : l10n.downloadPaused,
      DownloadStatus.failed => problemText(l10n, d!.problem),
      DownloadStatus.queued => l10n.downloadQueued,
      DownloadStatus.running =>
        progress == null && d!.downloadedBytes == 0
            ? l10n.downloadingStatus
            : context.joinMeta([
                l10n.downloadingStatus,
                '${(downloadFraction(d!, progress) * 100).floor()}%',
              ]),
    };
    return OutlinedButton.icon(
      onPressed: () => d == null
          ? startDownload(context, ref, item)
          : showDownloadMenu(context, ref, d),
      icon: downloadIcon(d, progress, size: 18, missing: missing),
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
    final missing = ref.watch(isDownloadMissingProvider(episode.id));
    return IconButton(
      tooltip: d == null
          ? l10n.downloadEpisode
          : d.status == DownloadStatus.complete
          ? (missing ? l10n.downloadFileRemoved : l10n.downloaded)
          : d.status == DownloadStatus.failed
          ? problemText(l10n, d.problem)
          : l10n.downloadingStatus,
      onPressed: () => d == null
          ? startDownload(context, ref, series, episode: episode)
          : showDownloadMenu(context, ref, d),
      style: IconButton.styleFrom(fixedSize: const Size.square(40)),
      icon: downloadIcon(d, progress, missing: missing),
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

/// Asks before throwing away an unfinished download, then cancels it.
Future<void> confirmCancel(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final sure = await showChoicePicker<bool>(
    context,
    title: l10n.downloadCancelTitle,
    selected: false,
    choices: [Choice(true, l10n.downloadCancel)],
  );
  if (sure != true) return;
  await ref.read(downloadsRepositoryProvider).cancel(d.videoId);
}

/// Asks, then deletes every downloaded episode of [titleId]. True when
/// deleted.
Future<bool> confirmDeleteTitle(
  BuildContext context,
  WidgetRef ref,
  String titleId,
  String title,
) async {
  final l10n = AppLocalizations.of(context);
  final sure = await showChoicePicker<bool>(
    context,
    title: title,
    selected: false,
    choices: [Choice(true, l10n.downloadDeleteAll)],
  );
  if (sure != true) return false;
  await ref.read(downloadsRepositoryProvider).deleteTitle(titleId);
  return true;
}

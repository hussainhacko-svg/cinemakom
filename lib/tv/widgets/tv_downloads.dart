import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/bulb_loader.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/media_text.dart';
import '../../data/models/download.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/repositories/downloads_repository.dart';
import '../../features/downloads/download_flow.dart';
import '../../features/player/quality.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import '../tv_navigation.dart';
import 'tv_button.dart';
import 'tv_choice_panel.dart';
import 'tv_focus_look.dart';

// Downloads on TV (docs/TV.md §7.4, the TV download panel design). The
// quality is asked each time, with sizes; a quality that wouldn't fit in the
// free space (keeping the engine's reserve) is shown but can't be picked.
// A download that exists opens what can be done with it. Deleting or
// cancelling asks first. Focus goes back to the button that opened a panel,
// which then shows the new state.

/// Downloads being prepared (their qualities and sizes are loading), so the
/// button can show it's working.
final _preparing = ValueNotifier<Set<String>>({});

Future<T?> _prepare<T>(String id, Future<T> Function() work) async {
  _preparing.value = {..._preparing.value, id};
  try {
    return await work();
  } finally {
    _preparing.value = {..._preparing.value}..remove(id);
  }
}

/// A short message with OK (a download that couldn't start).
Future<void> _say(BuildContext context, String title, String message) =>
    showTvChoicePanel<bool>(
      context,
      title: title,
      subtitle: message,
      choices: [TvChoice(true, AppLocalizations.of(context).tvOk)],
    );

/// "Episode 6" or the movie's title.
String _what(BuildContext context, MediaItem item, Episode? episode) {
  final l10n = AppLocalizations.of(context);
  return episode == null
      ? context.titleOf(item)
      : episodeLabel(l10n, episode.numbering);
}

/// Asks for a quality and downloads [item], or its [episode].
Future<void> tvStartDownload(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  Episode? episode,
}) async {
  final l10n = AppLocalizations.of(context);
  final id = episode?.id ?? item.id;
  final DownloadOffer? offer;
  final int? free;
  try {
    (offer, free) = (await _prepare(
      id,
      () async => (
        await downloadOffer(ref, id),
        await ref.read(downloadFreeSpaceProvider)(),
      ),
    ))!;
  } on Object catch (e) {
    if (context.mounted) {
      await _say(context, l10n.download, errorMessage(l10n, e));
    }
    return;
  }
  if (!context.mounted) return;
  if (offer == null) {
    await _say(context, l10n.download, l10n.downloadProblemUnavailable);
    return;
  }
  final picked = await _pickQuality(
    context,
    offer,
    free,
    title: _what(context, item, episode),
    subtitle: context.joinMeta([
      if (episode != null) ...[
        context.titleOf(item),
        l10n.seasonNumber(episode.season),
      ],
      ?switch (episode?.duration ?? item.duration) {
        final d? => formatDuration(l10n, d),
        null => null,
      },
    ]),
  );
  if (picked == null || !context.mounted) return;
  try {
    await queueDownload(ref, item, picked, episode: episode);
  } on Object {
    if (context.mounted) {
      await _say(context, l10n.download, l10n.downloadStartFailed);
    }
  }
}

/// Asks for a quality once and downloads every episode of [season] that
/// isn't on the TV yet (at most two run at once).
Future<void> tvStartSeasonDownload(
  BuildContext context,
  WidgetRef ref,
  MediaItem series,
  List<Episode> season,
) async {
  if (season.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final DownloadOffer? offer;
  final int? free;
  try {
    (offer, free) = (await _prepare(
      'season:${series.seriesId}',
      () async => (
        await downloadOffer(ref, season.first.id),
        await ref.read(downloadFreeSpaceProvider)(),
      ),
    ))!;
  } on Object catch (e) {
    if (context.mounted) {
      await _say(context, l10n.downloadSeason, errorMessage(l10n, e));
    }
    return;
  }
  if (!context.mounted || offer == null) return;
  final picked = await _pickQuality(
    context,
    offer,
    free,
    // The whole season must fit (rule 10), at about the first one's size.
    count: seasonEpisodesToQueue(ref, season),
    title: l10n.downloadSeason,
    subtitle: context.joinMeta([
      context.titleOf(series),
      l10n.seasonNumber(season.first.season),
      l10n.downloadEpisodeCount(season.length),
    ]),
    each: true,
  );
  if (picked == null || !context.mounted) return;
  final queued = await queueSeason(ref, series, season, picked);
  if (queued == 0 && context.mounted) {
    await _say(context, l10n.downloadSeason, l10n.downloadSeasonQueued(0));
  }
}

/// The quality panel: each quality with its size ("about … each" for a
/// season), opened on the preferred one; one that wouldn't fit is "Too big".
/// [count] episodes of a season must all fit.
Future<DownloadChoice?> _pickQuality(
  BuildContext context,
  DownloadOffer offer,
  int? free, {
  required String title,
  required String subtitle,
  bool each = false,
  int count = 1,
}) async {
  final l10n = AppLocalizations.of(context);
  String size(DownloadChoice c) => context.isolate(formatBytes(l10n, c.bytes!));
  bool fits(DownloadChoice c) =>
      downloadFits(c.bytes == null ? null : c.bytes! * count, free);
  final fitting = [
    for (final c in offer.choices)
      if (fits(c)) c,
  ];
  final freeLine = free == null
      ? null
      : l10n.tvFreeSpace(context.isolate(formatBytes(l10n, free)));
  // Nothing fits: say so, rather than a panel with nothing to pick.
  if (fitting.isEmpty) {
    await _say(
      context,
      title,
      [l10n.downloadProblemSpace, ?freeLine].join('\n'),
    );
    return null;
  }
  return showTvChoicePanel<DownloadChoice>(
    context,
    eyebrow: l10n.download,
    title: title,
    subtitle: subtitle,
    selected: fitting.contains(offer.preferred)
        ? offer.preferred
        : fitting.firstOrNull,
    footer: freeLine,
    choices: [
      for (final c in offer.choices)
        TvChoice(
          c,
          qualityChipLabel(c.source),
          enabled: fits(c),
          caption: c.bytes == null
              ? null
              : !fits(c)
              ? l10n.tvTooBig(size(c))
              : each
              ? l10n.tvAboutEach(size(c))
              : size(c),
        ),
    ],
  );
}

enum _Action {
  play,
  redownload,
  pause,
  resume,
  retry,
  details,
  cancel,
  delete,
  remove,
  open,
}

/// What can be done with [d]: play, details or delete a finished one; Download
/// again or Remove when its file was removed outside the app; pause, resume or
/// try again, details, cancel, or go to Downloads for an unfinished one.
Future<void> tvDownloadMenu(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  final progress = ref.read(progressOfProvider(d.videoId));
  final missing = ref.read(isDownloadMissingProvider(d.videoId));
  final title = d.isEpisode
      ? l10n.episodeNumber(d.episode!)
      : context.titleOf(d.item);
  final action = await showTvChoicePanel<_Action>(
    context,
    eyebrow: l10n.download,
    title: title,
    subtitle: missing
        ? l10n.downloadFileRemoved
        : tvDownloadStatus(l10n, d, progress),
    choices: switch (d.status) {
      DownloadStatus.complete when missing => [
        TvChoice(_Action.redownload, l10n.downloadAgain),
        TvChoice(_Action.details, l10n.downloadDetails),
        TvChoice(_Action.remove, l10n.downloadRemove),
      ],
      DownloadStatus.complete => [
        TvChoice(_Action.play, l10n.play),
        TvChoice(_Action.details, l10n.downloadDetails),
        TvChoice(_Action.delete, l10n.downloadDelete),
      ],
      DownloadStatus.failed => [
        TvChoice(_Action.retry, l10n.retry),
        TvChoice(_Action.cancel, l10n.downloadCancel),
        TvChoice(_Action.details, l10n.downloadDetails),
        TvChoice(_Action.open, l10n.tvGoToDownloads),
      ],
      DownloadStatus.paused => [
        TvChoice(_Action.resume, l10n.downloadResume),
        TvChoice(_Action.cancel, l10n.downloadCancel),
        TvChoice(_Action.details, l10n.downloadDetails),
        TvChoice(_Action.open, l10n.tvGoToDownloads),
      ],
      _ => [
        TvChoice(_Action.pause, l10n.downloadPause),
        TvChoice(_Action.cancel, l10n.downloadCancel),
        TvChoice(_Action.details, l10n.downloadDetails),
        TvChoice(_Action.open, l10n.tvGoToDownloads),
      ],
    },
  );
  if (!context.mounted) return;
  switch (action) {
    case _Action.play:
      tvOpenPlayer(context, d.request);
    case _Action.redownload:
      await tvRedownload(context, ref, d);
    case _Action.pause:
      await repo.pause(d.videoId);
    case _Action.resume || _Action.retry:
      await tvResumeDownload(context, ref, d);
    case _Action.details:
      final path = await repo.filePath(d);
      if (!context.mounted) return;
      final sizes = downloadSizesLabel(l10n, d, progress);
      final lines = [
        missing
            ? l10n.downloadFileRemoved
            : tvDownloadStatus(l10n, d, progress),
        ?sizes,
        if (d.problemDetail case final detail? when detail.isNotEmpty) detail,
        path,
      ];
      await _say(context, l10n.downloadDetails, lines.join('\n'));
    case _Action.cancel:
      if (await tvConfirm(
        context,
        l10n.downloadCancel,
        l10n.downloadCancelTitle,
        l10n.tvKeepDownloading,
      )) {
        await repo.cancel(d.videoId);
      }
    case _Action.remove:
      await repo.delete(d.videoId);
    case _Action.delete:
      if (await tvConfirm(
        context,
        l10n.downloadDelete,
        l10n.tvDeleteQuestion,
        l10n.tvKeepIt,
      )) {
        await repo.delete(d.videoId);
      }
    case _Action.open:
      context.go('/downloads');
    case null:
      break;
  }
}

/// Resumes or retries [d] on TV, when the rest of it fits (rule 10). If the
/// stored quality is gone, asks the user before switching quality and
/// starting over (docs/DOWNLOADS.md §5.5).
Future<void> tvResumeDownload(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final repo = ref.read(downloadsRepositoryProvider);
  if (!await _tvFits(context, ref, d)) return;
  final outcome = await repo.resume(d.videoId);
  if (!context.mounted) return;
  if (outcome case ResumeQualityGone(:final previousQuality, :final fallback)) {
    if (await _tvConfirmSwitch(context, ref, d, previousQuality, fallback) &&
        context.mounted) {
      await repo.resume(d.videoId, switchTo: fallback);
    }
  }
}

/// Downloads again a finished download whose file was removed outside the
/// app (§5.8), asking first when its quality is gone.
Future<void> tvRedownload(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(downloadsRepositoryProvider);
  if (!await _tvFits(context, ref, d)) return;
  final outcome = await repo.redownload(d.videoId);
  if (!context.mounted) return;
  switch (outcome) {
    case ResumeQualityGone(:final previousQuality, :final fallback):
      if (await _tvConfirmSwitch(context, ref, d, previousQuality, fallback) &&
          context.mounted) {
        await repo.redownload(d.videoId, switchTo: fallback);
      }
    case ResumeFailed(:final problem?):
      await _say(context, l10n.downloadAgain, problemText(l10n, problem));
    case ResumeStarted() || ResumeFailed():
      break;
  }
}

/// Whether what [d] still needs fits on the TV (another quality's [bytes]
/// when given); says how much is missing when it doesn't.
Future<bool> _tvFits(
  BuildContext context,
  WidgetRef ref,
  Download d, {
  int? bytes,
}) async {
  final deficit = await downloadSpaceShortfall(ref, d, bytes: bytes);
  if (deficit <= 0) return true;
  if (context.mounted) {
    final l10n = AppLocalizations.of(context);
    await _say(
      context,
      l10n.download,
      l10n.downloadSpaceNeeded(formatBytes(l10n, deficit)),
    );
  }
  return false;
}

Future<bool> _tvConfirmSwitch(
  BuildContext context,
  WidgetRef ref,
  Download d,
  String previousQuality,
  VideoSource fallback,
) async {
  final l10n = AppLocalizations.of(context);
  final sure = await tvConfirm(
    context,
    l10n.downloadSwitchQuality(qualityChipLabel(fallback)),
    l10n.downloadQualityGoneTitle(previousQuality),
    l10n.tvKeepIt,
  );
  if (!sure || !context.mounted) return false;
  final bytes = await ref.read(downloadsRepositoryProvider).sizeOf(fallback);
  if (!context.mounted) return false;
  return _tvFits(context, ref, d, bytes: bytes);
}

/// Asks before something that can't be undone. Opens on [keep], so a
/// quick OK never deletes.
Future<bool> tvConfirm(
  BuildContext context,
  String doIt,
  String question,
  String keep,
) async =>
    await showTvChoicePanel<bool>(
      context,
      title: doIt,
      subtitle: question,
      selected: false,
      choices: [TvChoice(false, keep), TvChoice(true, doIt)],
    ) ??
    false;

/// Why a failed download stopped, as the phone's Details shows it: the
/// reason, the engine's message (shortened) and what's saved, then Try again
/// (focused) or OK. The file's path is left out: a TV has nowhere to open it.
Future<void> tvDownloadDetails(
  BuildContext context,
  WidgetRef ref,
  Download d,
) async {
  final l10n = AppLocalizations.of(context);
  final sizes = downloadSizesLabel(
    l10n,
    d,
    ref.read(progressOfProvider(d.videoId)),
  );
  var detail = d.problemDetail ?? '';
  if (detail.length > 240) detail = '${detail.substring(0, 240)}…';
  final retry = await showTvChoicePanel<bool>(
    context,
    title: l10n.downloadDetails,
    subtitle: [
      '${l10n.downloadDetailReason}: ${problemText(l10n, d.problem)}',
      if (detail.isNotEmpty)
        '${l10n.downloadDetailEngine}: ${context.isolate(detail)}',
      if (sizes != null)
        '${l10n.downloadDetailProgress}: ${context.isolate(sizes)}',
    ].join('\n'),
    selected: true,
    choices: [TvChoice(true, l10n.retry), TvChoice(false, l10n.tvOk)],
  );
  if (retry == true && context.mounted) await tvResumeDownload(context, ref, d);
}

/// "Downloading · 42%", "Waiting", "Paused", "Waiting for connection", the
/// problem, "File removed" ([missing]) or "Downloaded".
String tvDownloadStatus(
  AppLocalizations l10n,
  Download d,
  DownloadProgress? progress, {
  bool missing = false,
}) => switch (d.status) {
  DownloadStatus.complete when missing => l10n.downloadFileRemoved,
  DownloadStatus.queued => l10n.downloadQueued,
  DownloadStatus.running => l10n.tvDownloadingPercent(
    (downloadFraction(d, progress) * 100).round(),
  ),
  DownloadStatus.paused =>
    d.isWaitingForConnection
        ? l10n.downloadWaitingConnection
        : l10n.downloadPaused,
  DownloadStatus.failed => problemText(l10n, d.problem),
  DownloadStatus.complete => l10n.downloaded,
};

/// An episode's round download button, item [index] of its zone (the TV
/// episodes design): ⇩, a ring with the percentage while it runs, ⏸ when
/// paused, an `ember` mark when it failed, a `bulb` ✓ when done. 52 dp,
/// `booth` with a `velvet` edge; focused, `boothRaised` with the ring.
class TvEpisodeDownloadButton extends ConsumerWidget {
  const TvEpisodeDownloadButton({
    super.key,
    required this.index,
    required this.series,
    required this.episode,
  });

  final int index;
  final MediaItem series;
  final Episode episode;

  static const double size = 52;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final d = ref.watch(downloadOfProvider(episode.id));
    final progress = ref.watch(progressOfProvider(episode.id));
    final missing = ref.watch(isDownloadMissingProvider(episode.id));
    final what = episodeLabel(l10n, episode.numbering);
    return ValueListenableBuilder(
      valueListenable: _preparing,
      builder: (context, preparing, _) => TvFocusable(
        index: index,
        label: d == null
            ? '${l10n.downloadEpisode}, $what'
            : '$what, ${tvDownloadStatus(l10n, d, progress, missing: missing)}',
        onSelect: () => d == null
            ? tvStartDownload(context, ref, series, episode: episode)
            : tvDownloadMenu(context, ref, d),
        builder: (context, focused) {
          final Widget inside;
          if (preparing.contains(episode.id)) {
            inside = const BulbLoader(count: 3, dotSize: 4, gap: 4);
          } else {
            inside = switch (d?.status) {
              null => const Icon(
                Icons.download_rounded,
                size: 22,
                color: MarqueeColors.cream,
              ),
              DownloadStatus.queued => const Icon(
                Icons.schedule,
                size: 22,
                color: MarqueeColors.dust,
              ),
              DownloadStatus.running || DownloadStatus.paused => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: size - 10,
                    child: CircularProgressIndicator(
                      value: downloadFraction(d!, progress).clamp(0.02, 1),
                      strokeWidth: 3,
                      color: d.status == DownloadStatus.paused
                          ? MarqueeColors.dust
                          : MarqueeColors.bulb,
                      backgroundColor: MarqueeColors.velvet,
                    ),
                  ),
                  if (d.status == DownloadStatus.paused)
                    const Icon(Icons.pause, size: 18, color: MarqueeColors.dust)
                  else
                    Text(
                      '${(downloadFraction(d, progress) * 100).round()}',
                      style: text.caption.copyWith(
                        fontSize: 13,
                        color: MarqueeColors.cream,
                      ),
                    ),
                ],
              ),
              DownloadStatus.failed => const Icon(
                Icons.error_outline,
                size: 22,
                color: MarqueeColors.ember,
              ),
              DownloadStatus.complete when missing => const Icon(
                Icons.error_outline,
                size: 22,
                color: MarqueeColors.ember,
              ),
              DownloadStatus.complete => const Icon(
                Icons.check,
                size: 24,
                color: MarqueeColors.bulb,
              ),
            };
          }
          return TvRing(
            on: focused,
            radius: TvRing.pill,
            gap: TvFocusStyle.buttonGap,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused
                    ? MarqueeColors.boothRaised
                    : MarqueeColors.booth,
                border: Border.all(color: MarqueeColors.velvet),
              ),
              child: inside,
            ),
          );
        },
      ),
    );
  }
}

/// A movie's Download button in Details' actions, item [index]: its label
/// follows the state ("Download", "Downloading · 42%", "Downloaded", …).
class TvMovieDownloadButton extends ConsumerWidget {
  const TvMovieDownloadButton({
    super.key,
    required this.index,
    required this.item,
  });

  final int index;
  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final d = ref.watch(downloadOfProvider(item.id));
    final progress = ref.watch(progressOfProvider(item.id));
    final missing = ref.watch(isDownloadMissingProvider(item.id));
    return TvButton(
      index: index,
      icon: d?.status == DownloadStatus.complete && !missing
          ? Icons.check
          : Icons.download_rounded,
      label: d == null
          ? l10n.download
          : tvDownloadStatus(l10n, d, progress, missing: missing),
      onSelect: () => d == null
          ? tvStartDownload(context, ref, item)
          : tvDownloadMenu(context, ref, d),
    );
  }
}

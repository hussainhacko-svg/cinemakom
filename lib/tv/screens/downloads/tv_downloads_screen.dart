import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/models/download.dart';
import '../../../data/repositories/downloads_repository.dart';
import '../../../features/downloads/download_flow.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_downloads.dart';
import '../../widgets/tv_shelf.dart';

/// The TV's free space, read again whenever the downloads change.
final _freeSpaceProvider = FutureProvider.autoDispose<int?>((ref) {
  ref.watch(downloadsProvider);
  return ref.read(downloadFreeSpaceProvider)();
});

/// Downloads on TV (docs/TV.md §7.7, docs/DOWNLOADS.md §5.10): what they
/// take and what's free (not focusable), then one list (zone 0), each row a
/// row of cells:
/// - downloading: the title (OK opens its Details) · Pause, Resume or Try
///   again · Cancel;
/// - a movie on the TV: the title (OK plays) · Delete;
/// - a series: one row (OK opens its episodes) · Delete all.
/// Cancel and Delete ask first, opening on the safe answer. Empty: what
/// goes here, and Browse Home. (The design's storage bar is left out, as on
/// the phone: the TV says how much is free instead.)
class TvDownloadsScreen extends ConsumerStatefulWidget {
  const TvDownloadsScreen({super.key});

  @override
  ConsumerState<TvDownloadsScreen> createState() => _TvDownloadsScreenState();
}

class _TvDownloadsScreenState extends ConsumerState<TvDownloadsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(downloadsRepositoryProvider).reconcile());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final all = ref.watch(downloadsProvider).value;
    final progress =
        ref.watch(downloadProgressProvider).value ??
        const <String, DownloadProgress>{};
    final free = ref.watch(_freeSpaceProvider).value;

    if (all == null) {
      return TvScreen(order: 1, builder: (_, _) => const SizedBox());
    }
    if (all.isEmpty) {
      return TvScreen(
        order: 1,
        builder: (context, scroll) => Align(
          alignment: Alignment.topCenter,
          child: TvEmpty(
            l10n.downloadsEmpty,
            action: TvZone.row(
              order: 0,
              keyline: 0,
              child: TvButton(
                index: 0,
                label: l10n.tvBrowseHome,
                onSelect: () => context.go('/home'),
              ),
            ),
          ),
        ),
      );
    }

    final active = all.where((d) => d.status.isActive).toList();
    // One row per movie or series on the TV, as on the phone.
    final titles = <String, List<Download>>{};
    for (final d in all.where((d) => !d.status.isActive)) {
      (titles[d.titleId] ??= []).add(d);
    }
    final rows = <Widget Function(int index)>[
      for (final d in active) (i) => _ActiveRow(index: i, download: d),
      for (final group in titles.values)
        (i) => _TitleRow(index: i, downloads: group),
    ];
    // As on the phone: files removed outside the app don't count, and the
    // engine's temp files do (§5.7).
    final used = downloadUsedBytes(
      all,
      progress,
      missing: ref.watch(downloadMissingProvider).value ?? const {},
      tempBytes: ref.watch(downloadStorageInfoProvider).value?.tempBytes ?? 0,
    );

    return TvScreen(
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              TvSpace.safeH,
              0,
              TvSpace.safeH,
              18,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      used > 0
                          ? l10n.downloadsUsed(formatBytes(l10n, used))
                          : '',
                      style: text.caption.copyWith(
                        color: MarqueeColors.creamSoft,
                      ),
                    ),
                  ),
                  if (free != null)
                    Text(
                      l10n.tvFreeSpace(formatBytes(l10n, free)),
                      style: text.caption,
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
            sliver: TvZone.grid(
              order: 0,
              columns: 3,
              keyline: 0,
              child: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => rows[i](i * 3),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: TvSpace.safeV)),
        ],
      ),
    );
  }
}

/// "Breaking Bad · S2 E6", or the movie's title.
String _title(BuildContext context, Download d) {
  final title = context.titleOf(d.item);
  if (!d.isEpisode) return title;
  final l10n = AppLocalizations.of(context);
  return context.joinMeta([
    title,
    l10n.seasonEpisodeShort(d.season!, d.episode!),
  ]);
}

/// A download still to finish: cells [index] to [index] + 2.
class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({required this.index, required this.download});

  final int index;
  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final d = download;
    final progress = ref.watch(progressOfProvider(d.videoId));
    final repo = ref.read(downloadsRepositoryProvider);
    final fraction = downloadFraction(d, progress);
    final sizes = downloadSizesLabel(l10n, d, progress);
    final percent = l10n.tvPercent((fraction * 100).round());
    // "42% · 1080p · 3.2 MB/s · 4 min left" with saved bytes in idle states.
    final meta = switch (d.status) {
      DownloadStatus.running => context.joinMeta([
        if (d.startedOver) l10n.downloadStartedOver,
        percent,
        ?sizes,
        d.quality,
        if (progress?.bytesPerSecond case final speed? when speed > 0)
          l10n.downloadSpeed(formatBytes(l10n, speed.round())),
        if (progress?.timeLeft case final left? when left > Duration.zero)
          minutesLeft(l10n, left),
      ]),
      DownloadStatus.queued => context.joinMeta([
        if (d.startedOver) l10n.downloadStartedOver else l10n.downloadQueued,
        ?sizes,
        d.quality,
      ]),
      DownloadStatus.paused => context.joinMeta([
        d.isWaitingForConnection
            ? l10n.downloadWaitingConnection
            : l10n.downloadPaused,
        ?sizes,
        if (sizes == null) percent,
        d.quality,
      ]),
      DownloadStatus.failed => context.joinMeta([
        problemText(l10n, d.problem),
        ?sizes,
      ]),
      DownloadStatus.complete => '',
    };
    final title = _title(context, d);
    final (String label, VoidCallback onSelect) = switch (d.status) {
      DownloadStatus.paused => (
        l10n.downloadResume,
        () => tvResumeDownload(context, ref, d),
      ),
      DownloadStatus.failed => (
        l10n.retry,
        () => tvResumeDownload(context, ref, d),
      ),
      _ => (l10n.downloadPause, () => repo.pause(d.videoId)),
    };
    return Row(
      children: [
        Expanded(
          child: TvShelfRow(
            index: index,
            label: context.joinMeta([title, meta]),
            title: title,
            posterUrl: d.posterUrl,
            lines: [meta],
            bar: fraction,
            barColor: d.status == DownloadStatus.running
                ? MarqueeColors.bulb
                : MarqueeColors.dust,
            onSelect: () => tvOpenTitle(context, d.item),
          ),
        ),
        const SizedBox(width: 14),
        TvButton(index: index + 1, label: label, onSelect: onSelect),
        const SizedBox(width: 14),
        TvButton(
          index: index + 2,
          label: l10n.tvCancel,
          onSelect: () async {
            if (await tvConfirm(
              context,
              l10n.downloadCancel,
              l10n.downloadCancelTitle,
              l10n.tvKeepDownloading,
            )) {
              await repo.cancel(d.videoId);
            }
          },
        ),
      ],
    );
  }
}

/// A movie, or a series' finished episodes as one row: cells [index] and
/// [index] + 1.
class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.index, required this.downloads});

  final int index;
  final List<Download> downloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final first = downloads.first;
    final repo = ref.read(downloadsRepositoryProvider);
    final series = first.isEpisode;
    final missingMovie =
        !series && ref.watch(isDownloadMissingProvider(first.videoId));
    final bytes = downloads.fold<int>(0, (a, d) => a + (d.totalBytes ?? 0));
    final title = context.titleOf(first.item);
    final meta = missingMovie
        ? l10n.downloadFileRemoved
        : context.joinMeta([
            if (series)
              l10n.downloadEpisodeCount(downloads.length)
            else ...[
              l10n.tvMovie,
              first.quality,
            ],
            if (bytes > 0) formatBytes(l10n, bytes),
          ]);
    return Row(
      children: [
        Expanded(
          child: TvShelfRow(
            index: index,
            label: context.joinMeta([title, meta]),
            title: title,
            posterUrl: first.posterUrl,
            lines: [meta],
            trailing: series
                ? const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: MarqueeColors.dust,
                  )
                : null,
            onSelect: () => series
                ? context.push('/downloads/saved/${first.titleId}')
                : missingMovie
                ? tvDownloadMenu(context, ref, first)
                : tvOpenPlayer(context, first.request),
          ),
        ),
        const SizedBox(width: 14),
        TvButton(
          index: index + 1,
          label: missingMovie
              ? l10n.downloadAgain
              : series
              ? l10n.downloadDeleteAll
              : l10n.tvDelete,
          onSelect: () async {
            if (missingMovie) {
              await tvRedownload(context, ref, first);
              return;
            }
            if (await tvConfirm(
              context,
              series ? l10n.downloadDeleteAll : l10n.downloadDelete,
              series ? title : l10n.tvDeleteQuestion,
              l10n.tvKeepIt,
            )) {
              await (series
                  ? repo.deleteTitle(first.titleId)
                  : repo.delete(first.videoId));
            }
          },
        ),
      ],
    );
  }
}

/// One series' episodes on the TV (a page pushed from Downloads): the
/// title, then the episodes in order (zone 0, each a row of cells: the
/// episode, OK plays it · Delete), then Delete all episodes (zone 1).
class TvSavedSeriesScreen extends ConsumerWidget {
  const TvSavedSeriesScreen({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final repo = ref.read(downloadsRepositoryProvider);
    final all = ref.watch(downloadsProvider).value ?? const <Download>[];
    final episodes =
        all
            .where(
              (d) =>
                  d.titleId == titleId && d.status == DownloadStatus.complete,
            )
            .toList()
          ..sort(
            (a, b) => a.season != b.season
                ? (a.season ?? 0).compareTo(b.season ?? 0)
                : (a.episode ?? 0).compareTo(b.episode ?? 0),
          );
    final title = episodes.isEmpty
        ? l10n.navDownloads
        : context.titleOf(episodes.first.item);
    return TvScreen(
      // The page's place in the tab shell, under the tabs.
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverPadding(
            padding: TvSpace.safe,
            sliver: SliverToBoxAdapter(
              child: Text(
                text.arabic ? title : title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.displayLarge.copyWith(fontSize: 36),
              ),
            ),
          ),
          if (episodes.isEmpty)
            SliverToBoxAdapter(
              child: TvEmpty(
                l10n.downloadsEmpty,
                action: TvZone.row(
                  order: 0,
                  keyline: 0,
                  child: TvButton(
                    index: 0,
                    label: l10n.tvBack,
                    onSelect: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
              sliver: TvZone.grid(
                order: 0,
                columns: 2,
                keyline: 0,
                child: SliverList.separated(
                  itemCount: episodes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = episodes[i];
                    final missing = ref.watch(
                      isDownloadMissingProvider(d.videoId),
                    );
                    final where =
                        '${l10n.seasonNumber(d.season!)} · '
                        '${episodeLabel(l10n, d.asEpisode!.numbering)}';
                    final meta = missing
                        ? l10n.downloadFileRemoved
                        : context.joinMeta([
                            d.quality,
                            if (d.totalBytes case final b? when b > 0)
                              formatBytes(l10n, b),
                          ]);
                    return Row(
                      children: [
                        Expanded(
                          child: TvShelfRow(
                            index: i * 2,
                            label: context.joinMeta([where, meta]),
                            title: where,
                            posterUrl: d.posterUrl,
                            lines: [meta],
                            onSelect: () => missing
                                ? tvDownloadMenu(context, ref, d)
                                : tvOpenPlayer(context, d.request),
                          ),
                        ),
                        const SizedBox(width: 14),
                        TvButton(
                          index: i * 2 + 1,
                          label: missing ? l10n.downloadAgain : l10n.tvDelete,
                          onSelect: () async {
                            if (missing) {
                              await tvRedownload(context, ref, d);
                              return;
                            }
                            if (await tvConfirm(
                              context,
                              l10n.downloadDelete,
                              l10n.tvDeleteQuestion,
                              l10n.tvKeepIt,
                            )) {
                              await repo.delete(d.videoId);
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: TvSpace.safe,
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TvZone.row(
                    order: 1,
                    keyline: 0,
                    child: TvButton(
                      index: 0,
                      icon: Icons.delete_outline_rounded,
                      label: l10n.downloadDeleteAll,
                      onSelect: () async {
                        if (await tvConfirm(
                              context,
                              l10n.downloadDeleteAll,
                              title,
                              l10n.tvKeepIt,
                            ) &&
                            context.mounted) {
                          await repo.deleteTitle(titleId);
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

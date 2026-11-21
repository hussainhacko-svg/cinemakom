import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/media_image.dart';
import '../../app/widgets/media_text.dart';
import '../../app/widgets/progress_line.dart';
import '../../app/widgets/section_header.dart';
import '../../app/widgets/sub_page.dart';
import '../../app/widgets/tab_page.dart';
import '../../data/models/download.dart';
import '../../data/repositories/downloads_repository.dart';
import 'download_actions.dart';
import 'download_flow.dart';

/// The Downloads tab (DESIGN.md §8, DOWNLOADS.md §5.10): the space used, then
/// **Downloading** (saved progress, speed, time left, pause or resume, cancel)
/// and **On this device** (movies, and each series as one row with its episode
/// count). Everything here plays offline.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(downloadsRepositoryProvider).reconcile());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final all = ref.watch(downloadsProvider).value;
    return TabPage(
      title: l10n.navDownloads,
      child: switch (all) {
        null => const SizedBox.shrink(),
        [] => _Empty(l10n.downloadsEmpty),
        final all => _Lists(all: all, gutter: gutter),
      },
    );
  }
}

class _Lists extends ConsumerWidget {
  const _Lists({required this.all, required this.gutter});

  final List<Download> all;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final active = all.where((d) => d.status.isActive).toList();
    final done = all.where((d) => !d.status.isActive).toList();
    // One row per movie or series, in the order they were last added to.
    final titles = <String, List<Download>>{};
    for (final d in done) {
      (titles[d.titleId] ??= []).add(d);
    }
    // Finished files, and what unfinished ones have saved on disk so far
    // (plus any engine temp files on disk, §5.7).
    final progress =
        ref.watch(downloadProgressProvider).value ??
        const <String, DownloadProgress>{};
    final storage = ref.watch(downloadStorageInfoProvider).value;
    final rowUsed = downloadUsedBytes(all, progress);
    final finishedBytes = done.fold<int>(0, (a, d) => a + (d.totalBytes ?? 0));
    final diskPartial = storage?.tempBytes ?? 0;
    final used = rowUsed > finishedBytes + diskPartial
        ? rowUsed
        : finishedBytes + diskPartial;
    final free = storage?.freeBytes;
    final storageLine = free != null
        ? l10n.downloadsStorageLine(
            formatBytes(l10n, used),
            formatBytes(l10n, free),
          )
        : used > 0
        ? l10n.downloadsUsed(formatBytes(l10n, used))
        : null;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        0,
        gutter,
        MarqueeSpace.huge,
      ),
      children: [
        if (storageLine != null) Text(storageLine, style: text.caption),
        if (active.isNotEmpty) ...[
          const SizedBox(height: MarqueeSpace.l),
          SectionHeader(title: l10n.downloadsDownloading),
          const SizedBox(height: MarqueeSpace.s),
          for (final d in active) _ActiveRow(download: d),
        ],
        if (titles.isNotEmpty) ...[
          const SizedBox(height: MarqueeSpace.l),
          SectionHeader(title: l10n.downloadsOnDevice),
          const SizedBox(height: MarqueeSpace.s),
          for (final group in titles.values) _TitleRow(downloads: group),
        ],
      ],
    );
  }
}

/// A `booth` row (radius 12) with a 48 × 72 poster.
class _Row extends StatelessWidget {
  const _Row({
    required this.posterUrl,
    required this.children,
    this.onTap,
    this.onMenu,
    this.trailing = const [],
  });

  final String? posterUrl;
  final List<Widget> children;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: MarqueeSpace.s),
    child: Material(
      color: MarqueeColors.booth,
      borderRadius: const BorderRadius.all(MarqueeRadius.card),
      child: InkWell(
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        onTap: onTap,
        onLongPress: onMenu,
        onSecondaryTap: onMenu,
        child: Padding(
          padding: const EdgeInsets.all(MarqueeSpace.s),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 72,
                child: MediaImage(
                  url: posterUrl,
                  borderRadius: const BorderRadius.all(MarqueeRadius.thumb),
                ),
              ),
              const SizedBox(width: MarqueeSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: children,
                ),
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    ),
  );
}

String _where(AppLocalizations l10n, Download d) => d.isEpisode
    ? '${l10n.seasonNumber(d.season!)} · ${episodeLabel(l10n, d.asEpisode!.numbering)}'
    : '';

class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({required this.download});

  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final d = download;
    final progress = ref.watch(progressOfProvider(d.videoId));
    final repo = ref.read(downloadsRepositoryProvider);
    final fraction = downloadFraction(d, progress);
    final sizes = downloadSizesLabel(l10n, d, progress);
    // Two caption lines: state + saved bytes, then live speed and time left.
    final status = switch (d.status) {
      DownloadStatus.running => context.joinMeta([
        if (d.startedOver) l10n.downloadStartedOver,
        ?sizes,
        if (sizes == null && !d.startedOver) l10n.downloadingStatus,
      ]),
      DownloadStatus.queued => context.joinMeta([
        if (d.startedOver) l10n.downloadStartedOver else l10n.downloadQueued,
        ?sizes,
      ]),
      DownloadStatus.paused => context.joinMeta([
        d.isWaitingForConnection
            ? l10n.downloadWaitingConnection
            : l10n.downloadPaused,
        ?sizes,
      ]),
      DownloadStatus.failed => context.joinMeta([
        problemText(l10n, d.problem),
        ?sizes,
      ]),
      DownloadStatus.complete => '',
    };
    final pace = d.status == DownloadStatus.running
        ? context.joinMeta([
            if (progress?.bytesPerSecond case final speed? when speed > 0)
              l10n.downloadSpeed(formatBytes(l10n, speed.round())),
            if (progress?.timeLeft case final left? when left > Duration.zero)
              minutesLeft(l10n, left),
          ])
        : '';
    final where = _where(l10n, d);
    final running =
        d.status == DownloadStatus.running || d.status == DownloadStatus.queued;
    return _Row(
      posterUrl: d.posterUrl,
      onMenu: () => showDownloadMenu(context, ref, d),
      trailing: [
        IconButton(
          tooltip: running
              ? l10n.downloadPause
              : d.status == DownloadStatus.failed
              ? l10n.retry
              : l10n.downloadResume,
          onPressed: () =>
              running ? repo.pause(d.videoId) : resumeDownload(context, ref, d),
          icon: Icon(
            running
                ? Icons.pause_rounded
                : d.status == DownloadStatus.failed
                ? Icons.refresh_rounded
                : Icons.play_arrow_rounded,
            size: 22,
          ),
        ),
        IconButton(
          tooltip: l10n.downloadCancel,
          onPressed: () => confirmCancel(context, ref, d),
          icon: const Icon(Icons.close_rounded, size: 22),
        ),
      ],
      children: [
        Text(
          context.titleOf(d.item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.label,
        ),
        if (where.isNotEmpty)
          Text(
            where,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.caption,
          ),
        const SizedBox(height: MarqueeSpace.s),
        // Full width, showing saved progress in every state (dimmed when idle).
        SizedBox(
          width: double.infinity,
          child: ProgressLine(
            value: fraction,
            track: MarqueeColors.velvetStrong,
            color: d.status == DownloadStatus.running
                ? MarqueeColors.bulb
                : MarqueeColors.dust,
          ),
        ),
        const SizedBox(height: MarqueeSpace.xs),
        Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: d.status == DownloadStatus.failed
              ? text.caption.copyWith(color: MarqueeColors.ember)
              : text.caption,
        ),
        if (pace.isNotEmpty)
          Text(
            pace,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.caption,
          ),
      ],
    );
  }
}

/// A finished movie (plays on tap), or a series (opens its episodes).
class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.downloads});

  final List<Download> downloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final first = downloads.first;
    final bytes = downloads.fold<int>(0, (a, d) => a + (d.totalBytes ?? 0));
    final series = first.isEpisode;
    final missingMovie =
        !series && ref.watch(isDownloadMissingProvider(first.videoId));
    final meta = missingMovie
        ? l10n.downloadFileRemoved
        : context.joinMeta([
            if (series)
              l10n.downloadEpisodeCount(downloads.length)
            else
              first.quality,
            if (bytes > 0) formatBytes(l10n, bytes),
          ]);
    return _Row(
      posterUrl: first.posterUrl,
      onTap: () => series
          ? context.push('/downloads/saved/${first.titleId}')
          : missingMovie
          ? showDownloadMenu(context, ref, first)
          : openPlayer(context, first.request),
      onMenu: series
          ? () => confirmDeleteTitle(
              context,
              ref,
              first.titleId,
              context.titleOf(first.item),
            )
          : () => showDownloadMenu(context, ref, first),
      trailing: [
        if (series)
          const Padding(
            padding: EdgeInsetsDirectional.only(end: MarqueeSpace.s),
            // Mirrors in RTL (the icon matches the text direction).
            child: Icon(Icons.chevron_right_rounded, color: MarqueeColors.dust),
          )
        else if (missingMovie)
          IconButton(
            tooltip: l10n.downloadAgain,
            onPressed: () =>
                ref.read(downloadsRepositoryProvider).redownload(first.videoId),
            icon: const Icon(
              Icons.refresh_rounded,
              size: 22,
              color: MarqueeColors.ember,
            ),
          )
        else
          IconButton(
            tooltip: l10n.play,
            onPressed: () => openPlayer(context, first.request),
            icon: const Icon(
              Icons.play_arrow_rounded,
              size: 22,
              color: MarqueeColors.bulb,
            ),
          ),
      ],
      children: [
        Text(
          context.titleOf(first.item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.label,
        ),
        const SizedBox(height: 2),
        Text(
          meta,
          style: missingMovie
              ? text.caption.copyWith(color: MarqueeColors.ember)
              : text.caption,
        ),
      ],
    );
  }
}

/// One series' downloaded episodes, in order, each playing offline.
class SavedSeriesScreen extends ConsumerWidget {
  const SavedSeriesScreen({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SubPageHeader(title: title, gutter: gutter),
            if (episodes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(l10n.downloadsEmpty),
              )
            else ...[
              SliverPadding(
                padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
                sliver: SliverList.list(
                  children: [
                    for (final d in episodes)
                      Builder(
                        builder: (context) {
                          final missing = ref.watch(
                            isDownloadMissingProvider(d.videoId),
                          );
                          return _Row(
                            posterUrl: d.posterUrl,
                            onTap: () => missing
                                ? showDownloadMenu(context, ref, d)
                                : openPlayer(context, d.request),
                            onMenu: () => showDownloadMenu(context, ref, d),
                            trailing: [
                              IconButton(
                                tooltip: l10n.downloadDelete,
                                onPressed: () =>
                                    showDownloadMenu(context, ref, d),
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            ],
                            children: [
                              Text(_where(l10n, d), style: text.label),
                              const SizedBox(height: 2),
                              Text(
                                missing
                                    ? l10n.downloadFileRemoved
                                    : context.joinMeta([
                                        d.quality,
                                        if (d.totalBytes case final b?
                                            when b > 0)
                                          formatBytes(l10n, b),
                                      ]),
                                style: missing
                                    ? text.caption.copyWith(
                                        color: MarqueeColors.ember,
                                      )
                                    : text.caption,
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    gutter,
                    MarqueeSpace.m,
                    gutter,
                    MarqueeSpace.huge,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (await confirmDeleteTitle(
                              context,
                              ref,
                              titleId,
                              title,
                            ) &&
                            context.mounted) {
                          context.pop();
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(l10n.downloadDeleteAll),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(MarqueeSpace.xxl),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: MarqueeText.of(context).body,
      ),
    ),
  );
}

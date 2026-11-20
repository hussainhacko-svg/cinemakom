import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../app/widgets/progress_line.dart';
import '../../../data/models/download.dart';
import '../../../data/repositories/downloads_repository.dart';
import '../../downloads/download_actions.dart';
import '../tv_shell.dart' show tvGutter;
import '../widgets/tv_focus.dart';

/// Dedicated 10-foot Android TV Downloads tab. Every row's actions (Pause /
/// Resume, Cancel, Play, Delete) are sibling buttons beside the row, so
/// D-pad Right always reaches them.
class TvDownloadsScreen extends ConsumerWidget {
  const TvDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(downloadsProvider).value;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvPageHeader(title: l10n.navDownloads),
          Expanded(
            child: switch (all) {
              null => const SizedBox.shrink(),
              [] => _Empty(l10n.downloadsEmpty),
              final all => _Lists(all: all),
            },
          ),
        ],
      ),
    );
  }
}

class _Lists extends ConsumerWidget {
  const _Lists({required this.all});

  final List<Download> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final active = all.where((d) => d.status.isActive).toList();
    final done = all.where((d) => !d.status.isActive).toList();
    final titles = <String, List<Download>>{};
    for (final d in done) {
      (titles[d.titleId] ??= []).add(d);
    }
    final progress =
        ref.watch(downloadProgressProvider).value ??
        const <String, DownloadProgress>{};
    var used = done.fold<int>(0, (a, d) => a + (d.totalBytes ?? 0));
    for (final d in active) {
      final p = progress[d.videoId];
      final total = p?.expectedBytes ?? d.totalBytes;
      if (p != null && total != null) used += (total * p.fraction).round();
    }
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        tvGutter,
        0,
        tvGutter,
        MarqueeSpace.huge,
      ),
      children: [
        if (used > 0)
          Text(
            l10n.downloadsUsed(formatBytes(l10n, used)),
            style: text.caption,
          ),
        if (active.isNotEmpty) ...[
          const SizedBox(height: MarqueeSpace.l),
          TvSectionHeader(title: l10n.downloadsDownloading),
          const SizedBox(height: MarqueeSpace.s),
          for (final d in active) _ActiveRow(download: d),
        ],
        if (titles.isNotEmpty) ...[
          const SizedBox(height: MarqueeSpace.l),
          TvSectionHeader(title: l10n.downloadsOnDevice),
          const SizedBox(height: MarqueeSpace.s),
          for (final group in titles.values) _TitleRow(downloads: group),
        ],
      ],
    );
  }
}

/// A `booth` row with a 48 × 72 HD poster; [actions] sit beside it as
/// sibling focus targets.
class _TvRow extends StatefulWidget {
  const _TvRow({
    required this.posterUrl,
    required this.children,
    required this.onTap,
    this.actions = const [],
  });

  final String? posterUrl;
  final List<Widget> children;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  State<_TvRow> createState() => _TvRowState();
}

class _TvRowState extends State<_TvRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: MarqueeSpace.s),
    child: Row(
      children: [
        Expanded(
          child: Material(
            color: _focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(MarqueeRadius.card),
              side: _focused
                  ? const BorderSide(color: MarqueeColors.bulb, width: 2)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onFocusChange: (f) {
                setState(() => _focused = f);
                if (f) tvEnsureVisible(context, alignment: 0.4);
              },
              focusColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(MarqueeSpace.s),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 72,
                      child: MediaImage(
                        url: widget.posterUrl,
                        borderRadius: const BorderRadius.all(
                          MarqueeRadius.thumb,
                        ),
                        decodeScale: 2.0,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(width: MarqueeSpace.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: widget.children,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final action in widget.actions) ...[
          const SizedBox(width: MarqueeSpace.s),
          action,
        ],
      ],
    ),
  );
}

/// A large labeled action button for TV rows.
class _TvAction extends StatelessWidget {
  const _TvAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 20, color: accent ? MarqueeColors.bulb : null),
    label: Text(label),
    style: OutlinedButton.styleFrom(minimumSize: const Size(120, 52)),
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
    final total = progress?.expectedBytes ?? d.totalBytes;
    final fraction = progress?.fraction ?? 0;
    final sizes = total == null
        ? null
        : l10n.downloadOf(
            formatBytes(l10n, (total * fraction).round()),
            formatBytes(l10n, total),
          );
    final status = switch (d.status) {
      DownloadStatus.running => sizes ?? '',
      DownloadStatus.queued => l10n.downloadQueued,
      DownloadStatus.paused => context.joinMeta([l10n.downloadPaused, ?sizes]),
      DownloadStatus.failed => problemText(l10n, d.problem),
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
    return _TvRow(
      posterUrl: d.posterUrl,
      onTap: () => showDownloadMenu(context, ref, d),
      actions: [
        _TvAction(
          icon: running
              ? Icons.pause_rounded
              : d.status == DownloadStatus.failed
              ? Icons.refresh_rounded
              : Icons.play_arrow_rounded,
          label: running
              ? l10n.downloadPause
              : d.status == DownloadStatus.failed
              ? l10n.retry
              : l10n.downloadResume,
          onPressed: () =>
              running ? repo.pause(d.videoId) : repo.resume(d.videoId),
        ),
        _TvAction(
          icon: Icons.close_rounded,
          label: l10n.downloadCancel,
          onPressed: () => confirmCancel(context, ref, d),
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
        SizedBox(
          width: double.infinity,
          child: ProgressLine(
            value: fraction,
            track: MarqueeColors.velvetStrong,
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
    final meta = context.joinMeta([
      if (series)
        l10n.downloadEpisodeCount(downloads.length)
      else
        first.quality,
      if (bytes > 0) formatBytes(l10n, bytes),
    ]);
    final title = context.titleOf(first.item);
    return _TvRow(
      posterUrl: first.posterUrl,
      onTap: () => series
          ? context.push('/downloads/saved/${first.titleId}')
          : openPlayer(context, first.request),
      actions: [
        if (!series)
          _TvAction(
            icon: Icons.play_arrow_rounded,
            label: l10n.play,
            accent: true,
            onPressed: () => openPlayer(context, first.request),
          ),
        _TvAction(
          icon: Icons.delete_outline_rounded,
          label: l10n.downloadDelete,
          onPressed: () => series
              ? confirmDeleteTitle(context, ref, first.titleId, title)
              : showDownloadMenu(context, ref, first),
        ),
      ],
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.label,
        ),
        const SizedBox(height: 2),
        Text(meta, style: text.caption),
      ],
    );
  }
}

/// One series' downloaded episodes on TV, each with sibling Play and Delete
/// buttons.
class TvSavedSeriesScreen extends ConsumerWidget {
  const TvSavedSeriesScreen({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: TvPageHeader(title: title)),
          if (episodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(l10n.downloadsEmpty),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: tvGutter,
              ),
              sliver: SliverList.list(
                children: [
                  for (final d in episodes)
                    _TvRow(
                      posterUrl: d.posterUrl,
                      onTap: () => openPlayer(context, d.request),
                      actions: [
                        _TvAction(
                          icon: Icons.delete_outline_rounded,
                          label: l10n.downloadDelete,
                          onPressed: () => showDownloadMenu(context, ref, d),
                        ),
                      ],
                      children: [
                        Text(_where(l10n, d), style: text.label),
                        const SizedBox(height: 2),
                        Text(
                          context.joinMeta([
                            d.quality,
                            if (d.totalBytes case final b? when b > 0)
                              formatBytes(l10n, b),
                          ]),
                          style: text.caption,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  tvGutter,
                  MarqueeSpace.m,
                  tvGutter,
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

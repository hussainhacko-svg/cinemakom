import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/catalog_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/error_view.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../app/widgets/progress_line.dart';
import '../../../data/models/catalog_models.dart';
import '../../../data/models/download.dart';
import '../../../data/models/media_details.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/playback_models.dart';
import '../../../data/models/playback_request.dart';
import '../../../data/models/watch_progress.dart';
import '../../../data/repositories/library_repository.dart';
import '../../details/details_providers.dart';
import '../../details/widgets/episode_list.dart' show episodeBlockSize;
import '../../downloads/download_actions.dart';
import '../../library/widgets/favorite_button.dart';
import '../../staff/widgets/person_photo.dart';
import '../tv_shell.dart' show tvGutter, tvPrimaryFocusLabel;
import '../widgets/tv_focus.dart';
import '../widgets/tv_media_row.dart';

/// Dedicated 10-foot Android TV Details screen:
/// - No phone BackPill (hardware Back pops).
/// - Two-column header: large 200×300 HD poster + title, metadata, actions
///   (Play autofocused, Favorite, movie Download, Trailer), synopsis, genres.
/// - Spacious TV episode rows with a **big, clearly labeled sibling Download
///   button** right beside every episode (D-pad Right to reach, crisp `bulb`
///   focus ring, zero nested InkWell traps).
/// - TV cast & crew row and "More like this" HD poster row.
class TvDetailsScreen extends ConsumerStatefulWidget {
  const TvDetailsScreen({super.key, required this.id, this.args});

  final String id;
  final TitleArgs? args;

  @override
  ConsumerState<TvDetailsScreen> createState() => _TvDetailsScreenState();
}

class _TvDetailsScreenState extends ConsumerState<TvDetailsScreen> {
  final _playFocus = FocusNode(debugLabel: tvPrimaryFocusLabel);
  bool _initialFocusRequested = false;

  @override
  void dispose() {
    _playFocus.dispose();
    super.dispose();
  }

  void _maybeFocusPlay() {
    if (_initialFocusRequested) return;
    _initialFocusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playFocus.canRequestFocus) {
        _playFocus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = ref.watch(detailsProvider(widget.id));
    final record = details.value;
    final item = record?.item ?? widget.args?.item;

    if (item == null) {
      if (details.hasError) {
        return Scaffold(
          body: ErrorView(
            error: details.error!,
            onRetry: () => ref.invalidate(detailsProvider(widget.id)),
          ),
        );
      }
      if (details.isLoading) {
        return Scaffold(
          body: Center(child: BulbLoader(semanticLabel: l10n.loading)),
        );
      }
      return Scaffold(
        body: Center(
          child: Text(
            l10n.titleUnavailable,
            style: MarqueeText.of(context).body,
          ),
        ),
      );
    }

    _maybeFocusPlay();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsetsDirectional.only(
          top: MarqueeSpace.l,
          bottom: MarqueeSpace.huge,
        ),
        children: [
          _TvDetailsHeader(
            item: item,
            details: record,
            playFocusNode: _playFocus,
          ),
          if (record == null && details.hasError)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                tvGutter,
                MarqueeSpace.l,
                tvGutter,
                0,
              ),
              child: ErrorView(
                error: details.error!,
                onRetry: () => ref.invalidate(detailsProvider(widget.id)),
                compact: true,
              ),
            ),
          if (item.isSeries)
            _TvEpisodeSection(
              series: item,
              initialSeason: widget.args?.item.rootSeriesId != null
                  ? widget.args?.item.season
                  : null,
            ),
          if (record != null) _TvCreditsRow(details: record),
          _TvMoreLikeThis(id: widget.id),
        ],
      ),
    );
  }
}

class _TvDetailsHeader extends ConsumerWidget {
  const _TvDetailsHeader({
    required this.item,
    required this.details,
    required this.playFocusNode,
  });

  final MediaItem item;
  final MediaDetails? details;
  final FocusNode playFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final arabic = context.isArabicUi;
    final title = context.titleOf(item);
    final arabicTitle = MarqueeText.hasArabic(title);
    final details = this.details;

    final meta = [
      if (item.year != null) '${item.year}',
      ...item.categories.take(3).map((c) => c.resolve(arabic: arabic) ?? ''),
      if (!item.isSeries && item.duration != null)
        formatDuration(l10n, item.duration!),
    ].where((s) => s.isNotEmpty).join(' · ');
    final audio = [
      for (final l in details?.audioLanguages ?? const [])
        ?l.resolve(arabic: arabic),
    ].join(', ');
    final external = details?.imdbUrl;
    final trailer = details?.trailerUrl;
    final description = item.description.resolve(arabic: arabic);

    const posterWidth = 200.0;
    final poster = SizedBox(
      width: posterWidth,
      height: posterWidth * 1.5,
      child: MediaImage(
        url: item.hdPosterUrl ?? item.posterUrl,
        borderRadius: const BorderRadius.all(MarqueeRadius.poster),
        decodeScale: 2.0,
        filterQuality: FilterQuality.medium,
      ),
    );

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: tvGutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          poster,
          const SizedBox(width: MarqueeSpace.xxxl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  arabicTitle ? title : title.toUpperCase(),
                  style: text.displayLargeFor(title),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: MarqueeSpace.s),
                  Text(meta, style: text.caption),
                ],
                if (audio.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(l10n.audioLanguages(audio), style: text.caption),
                ],
                if (external != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => _openExternal(external),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 36),
                      ),
                      child: Text(
                        details!.imdbUrlIsImdb ? 'IMDb' : 'MyAnimeList',
                      ),
                    ),
                  ),
                const SizedBox(height: MarqueeSpace.l),
                Wrap(
                  spacing: MarqueeSpace.m,
                  runSpacing: MarqueeSpace.m,
                  children: [
                    _TvPlayButton(item: item, focusNode: playFocusNode),
                    FavoritePill(item: item),
                    if (!item.isSeries) DownloadPill(item: item),
                    if (trailer != null)
                      OutlinedButton.icon(
                        onPressed: () => _openExternal(trailer),
                        icon: const Icon(Icons.smart_display_outlined, size: 18),
                        label: Text(l10n.trailer),
                      ),
                  ],
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: MarqueeSpace.l),
                  _TvSynopsis(description),
                ],
                _TvGenreChips(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _TvPlayButton extends ConsumerWidget {
  const _TvPlayButton({required this.item, required this.focusNode});

  final MediaItem item;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    var label = l10n.play;
    var request = PlaybackRequest(item: item);

    if (item.isSeries) {
      final watched =
          ref.watch(seriesProgressProvider(item.seriesId)).value ?? const {};
      final episodes =
          ref.watch(episodesProvider(item.seriesId)).value ?? const <Episode>[];
      final latest = watched.values.fold<WatchProgress?>(
        null,
        (a, b) => a == null || b.updatedAt.isAfter(a.updatedAt) ? b : a,
      );
      if (latest != null) {
        final i = episodes.indexWhere((e) => e.id == latest.videoId);
        final current = i < 0 ? null : episodes[i];
        String short(Episode e) => l10n.seasonEpisodeShort(e.season, e.episode);
        if (!latest.isFinished && current != null) {
          label = latest.resumeAt == null
              ? '${l10n.play} · ${short(current)}'
              : [
                  l10n.resume,
                  short(current),
                  minutesLeft(l10n, latest.remaining),
                ].join(' · ');
          request = PlaybackRequest(item: item, episode: current);
        } else if (latest.isFinished && i >= 0 && i + 1 < episodes.length) {
          final next = episodes[i + 1];
          label = '${l10n.play} · ${short(next)}';
          request = PlaybackRequest(item: item, episode: next);
        }
      }
    } else {
      final saved = ref.watch(watchProgressProvider(item.id)).value;
      if (saved?.resumeAt != null) {
        label = '${l10n.resume} · ${minutesLeft(l10n, saved!.remaining)}';
      }
    }

    return FilledButton.icon(
      focusNode: focusNode,
      onPressed: () => openPlayer(context, request),
      icon: const Icon(Icons.play_arrow_rounded, size: 22),
      label: Text(label),
    );
  }
}

class _TvSynopsis extends StatefulWidget {
  const _TvSynopsis(this.text);

  final String text;

  @override
  State<_TvSynopsis> createState() => _TvSynopsisState();
}

class _TvSynopsisState extends State<_TvSynopsis> {
  bool _expanded = false;
  static const _lines = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = MarqueeText.of(context).body;
    return LayoutBuilder(
      builder: (context, box) {
        final overflows = (TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth)).didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _lines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                ),
                child: Text(_expanded ? l10n.showLess : l10n.showMore),
              ),
          ],
        );
      },
    );
  }
}

class _TvGenreChips extends ConsumerWidget {
  const _TvGenreChips({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arabic = context.isArabicUi;
    final genres = ref.watch(genresProvider).value ?? const <Category>[];
    Category? match(String? en, String? ar) {
      for (final g in genres) {
        if ((en != null && g.name.en == en) ||
            (ar != null && g.name.ar == ar)) {
          return g;
        }
      }
      return null;
    }

    final chips = [
      for (final c in item.categories)
        if (c.resolve(arabic: arabic) case final name?)
          if (match(c.en, c.ar) case final genre?) (name, genre),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.m),
      child: Wrap(
        spacing: MarqueeSpace.s,
        runSpacing: MarqueeSpace.s,
        children: [
          for (final (name, genre) in chips)
            TvPill(
              label: name,
              selected: false,
              onTap: () => openGenre(context, genre),
            ),
        ],
      ),
    );
  }
}

/// TV Episodes section with season/block pills, "Download season", and
/// spacious episode rows where the episode Play card and its big Download
/// button are clean sibling focus targets.
class _TvEpisodeSection extends ConsumerStatefulWidget {
  const _TvEpisodeSection({required this.series, this.initialSeason});

  final MediaItem series;
  final int? initialSeason;

  @override
  ConsumerState<_TvEpisodeSection> createState() => _TvEpisodeSectionState();
}

class _TvEpisodeSectionState extends ConsumerState<_TvEpisodeSection> {
  int? _season;
  int? _block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seriesId = widget.series.seriesId;
    final episodes = ref.watch(episodesProvider(seriesId));
    final all = episodes.value ?? const <Episode>[];
    final watched =
        ref.watch(seriesProgressProvider(seriesId)).value ?? const {};

    final Widget body;
    if (all.isEmpty) {
      body = episodes.hasError && !episodes.isLoading
          ? ErrorView(
              error: episodes.error!,
              onRetry: () => ref.invalidate(episodesProvider(seriesId)),
              compact: true,
            )
          : episodes.isLoading
          ? Padding(
              padding: const EdgeInsets.all(MarqueeSpace.xxl),
              child: Center(child: BulbLoader(semanticLabel: l10n.loading)),
            )
          : const SizedBox.shrink();
    } else {
      final anchorId = watched.values
          .fold<WatchProgress?>(
            null,
            (a, b) => a == null || b.updatedAt.isAfter(a.updatedAt) ? b : a,
          )
          ?.videoId;
      final anchor = [
        for (final e in all)
          if (e.id == anchorId) e,
      ].firstOrNull;
      final seasons = {for (final e in all) e.season}.toList()..sort();
      final season = seasons.contains(_season)
          ? _season!
          : seasons.contains(widget.initialSeason)
          ? widget.initialSeason!
          : anchor?.season ?? seasons.first;
      final inSeason = [
        for (final e in all)
          if (e.season == season) e,
      ];
      final blocks = (inSeason.length / episodeBlockSize).ceil();
      final anchorAt = anchor == null ? -1 : inSeason.indexOf(anchor);
      final block =
          (_block ?? (anchorAt < 0 ? 0 : anchorAt ~/ episodeBlockSize)).clamp(
            0,
            blocks - 1,
          );
      final shown = inSeason
          .skip(block * episodeBlockSize)
          .take(episodeBlockSize)
          .toList();

      final numeralStyle = DefaultTextStyle.of(context).style
          .merge(MarqueeText.of(context).numeral);
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final numeralWidth = shown.fold<double>(56, (widest, e) {
        final painter = TextPainter(
          text: TextSpan(text: _numeralText(e), style: numeralStyle),
          maxLines: 1,
          textDirection: direction,
          textScaler: scaler,
        )..layout();
        final width = painter.width.ceilToDouble();
        painter.dispose();
        return math.max(widest, width);
      });

      String range(int b) {
        final first = inSeason[b * episodeBlockSize].numbering.first;
        final last =
            inSeason[math.min((b + 1) * episodeBlockSize, inSeason.length) - 1]
                .numbering
                .last;
        return first == last ? '$first' : l10n.episodeRange(first, last);
      }

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (seasons.length > 1)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: MarqueeSpace.s),
                itemBuilder: (_, i) => TvPill(
                  label: l10n.seasonNumber(seasons[i]),
                  selected: seasons[i] == season,
                  onTap: () => setState(() {
                    _season = seasons[i];
                    _block = null;
                  }),
                ),
              ),
            ),
          if (blocks > 1) ...[
            if (seasons.length > 1) const SizedBox(height: MarqueeSpace.s),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: blocks,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: MarqueeSpace.s),
                itemBuilder: (_, b) => TvPill(
                  label: range(b),
                  selected: b == block,
                  onTap: () => setState(() => _block = b),
                ),
              ),
            ),
          ],
          const SizedBox(height: MarqueeSpace.m),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SeasonDownloadButton(
              series: widget.series,
              season: inSeason,
            ),
          ),
          const SizedBox(height: MarqueeSpace.m),
          for (final episode in shown)
            _TvEpisodeRow(
              series: widget.series,
              episode: episode,
              progress: watched[episode.id],
              numeralWidth: numeralWidth,
              onPlay: () => openPlayer(
                context,
                PlaybackRequest(item: widget.series, episode: episode),
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        tvGutter,
        MarqueeSpace.xxl,
        tvGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvSectionHeader(title: l10n.episodesHeading),
          const SizedBox(height: MarqueeSpace.m),
          body,
        ],
      ),
    );
  }
}

String _numeralText(Episode e) => '${e.numbering.first}'.padLeft(2, '0');

/// Spacious 10-foot episode row:
/// - Left (Expanded): focusable Play episode card (`bulb` 2 px ring).
/// - Right (Sibling): big, clearly labeled focusable Download button (D-pad
///   Right to reach, `bulb` 2 px ring). Zero nested `InkWell`s.
class _TvEpisodeRow extends StatefulWidget {
  const _TvEpisodeRow({
    required this.series,
    required this.episode,
    required this.numeralWidth,
    required this.onPlay,
    this.progress,
  });

  final MediaItem series;
  final Episode episode;
  final WatchProgress? progress;
  final double numeralWidth;
  final VoidCallback onPlay;

  @override
  State<_TvEpisodeRow> createState() => _TvEpisodeRowState();
}

class _TvEpisodeRowState extends State<_TvEpisodeRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final episode = widget.episode;
    final numbering = episode.numbering;
    final duration = episode.duration;
    final progress = widget.progress;
    final finished = progress?.isFinished ?? false;
    final started = progress != null && !finished;

    return Padding(
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
                    : const BorderSide(color: MarqueeColors.velvet),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onPlay,
                onFocusChange: (f) {
                  setState(() => _focused = f);
                  if (f) tvEnsureVisible(context, alignment: 0.4);
                },
                focusColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: widget.numeralWidth,
                          child: Text(
                            _numeralText(episode),
                            maxLines: 1,
                            softWrap: false,
                            style: text.numeral.copyWith(
                              color: started || _focused
                                  ? MarqueeColors.bulb
                                  : finished
                                  ? MarqueeColors.cream
                                  : MarqueeColors.dustDim,
                            ),
                          ),
                        ),
                        const SizedBox(width: MarqueeSpace.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      episodeLabel(l10n, numbering),
                                      style: _focused
                                          ? text.label.copyWith(
                                              color: MarqueeColors.bulb,
                                              fontSize: 16,
                                            )
                                          : text.label.copyWith(fontSize: 16),
                                    ),
                                  ),
                                  if (numbering.isFinale) ...[
                                    const SizedBox(width: MarqueeSpace.s),
                                    _TvBadge(l10n.finalEpisode),
                                  ],
                                ],
                              ),
                              if (started)
                                Text(
                                  minutesLeft(l10n, progress.remaining),
                                  style: text.caption,
                                )
                              else if (duration != null)
                                Text(
                                  formatDuration(l10n, duration),
                                  style: text.caption,
                                ),
                              if (started) ...[
                                const SizedBox(height: MarqueeSpace.xs),
                                ProgressLine(value: progress.fraction),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: MarqueeSpace.m),
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 26,
                          color: _focused
                              ? MarqueeColors.bulb
                              : MarqueeColors.dust,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: MarqueeSpace.m),
          _TvEpisodeDownloadButton(series: widget.series, episode: episode),
        ],
      ),
    );
  }
}

/// Big, clearly labeled focusable Download button beside each TV episode row.
class _TvEpisodeDownloadButton extends ConsumerStatefulWidget {
  const _TvEpisodeDownloadButton({
    required this.series,
    required this.episode,
  });

  final MediaItem series;
  final Episode episode;

  @override
  ConsumerState<_TvEpisodeDownloadButton> createState() =>
      _TvEpisodeDownloadButtonState();
}

class _TvEpisodeDownloadButtonState
    extends ConsumerState<_TvEpisodeDownloadButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final d = ref.watch(downloadOfProvider(widget.episode.id));
    final progress = ref.watch(progressOfProvider(widget.episode.id));

    final label = switch (d?.status) {
      null => l10n.download,
      DownloadStatus.complete => l10n.downloaded,
      DownloadStatus.paused => l10n.downloadPaused,
      DownloadStatus.failed => l10n.retry,
      DownloadStatus.queued => l10n.downloadQueued,
      DownloadStatus.running =>
        progress == null
            ? l10n.downloadingStatus
            : '${(progress.fraction * 100).floor()}%',
    };
    final tooltip = d == null
        ? l10n.downloadEpisode
        : d.status == DownloadStatus.complete
        ? l10n.downloaded
        : d.status == DownloadStatus.failed
        ? problemText(l10n, d.problem)
        : l10n.downloadingStatus;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: _focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(MarqueeRadius.card),
            side: _focused
                ? const BorderSide(color: MarqueeColors.bulb, width: 2)
                : BorderSide(
                    color: d?.status == DownloadStatus.complete
                        ? MarqueeColors.bulb
                        : MarqueeColors.velvetStrong,
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => d == null
                ? startDownload(
                    context,
                    ref,
                    widget.series,
                    episode: widget.episode,
                  )
                : showDownloadMenu(context, ref, d),
            onFocusChange: (f) {
              setState(() => _focused = f);
              if (f) tvEnsureVisible(context, alignment: 0.4);
            },
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 148, minHeight: 72),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    downloadIcon(d, progress, size: 22),
                    const SizedBox(width: MarqueeSpace.s),
                    Text(
                      label,
                      style: text.label.copyWith(
                        color: _focused || d?.status == DownloadStatus.complete
                            ? MarqueeColors.bulb
                            : MarqueeColors.cream,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvBadge extends StatelessWidget {
  const _TvBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: MarqueeColors.velvetStrong),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        text.arabic ? label : label.toUpperCase(),
        style: text.caption.copyWith(
          fontSize: 11,
          color: MarqueeColors.cream,
          letterSpacing: text.arabic ? 0 : 0.6,
        ),
      ),
    );
  }
}

class _TvCreditsRow extends StatelessWidget {
  const _TvCreditsRow({required this.details});

  final MediaDetails details;

  static const _maxPeople = 16;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seen = <String>{};
    final people = [
      for (final p in [
        ...details.directors,
        ...details.actors,
        ...details.writers,
      ])
        if (seen.add(p.id)) p,
    ].take(_maxPeople).toList();
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: tvGutter,
            ),
            child: TvSectionHeader(title: l10n.castAndCrew),
          ),
          const SizedBox(height: MarqueeSpace.m),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: tvGutter,
              ),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (_, i) => _TvPersonCard(credit: people[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvPersonCard extends StatefulWidget {
  const _TvPersonCard({required this.credit});

  final StaffCredit credit;

  @override
  State<_TvPersonCard> createState() => _TvPersonCardState();
}

class _TvPersonCardState extends State<_TvPersonCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final credit = widget.credit;
    final role = switch (credit.role) {
      StaffRole.actor => l10n.roleActor,
      StaffRole.director => l10n.roleDirector,
      StaffRole.writer => l10n.roleWriter,
      StaffRole.other => '',
    };
    return Semantics(
      button: true,
      label: role.isEmpty ? credit.name : '${credit.name}, $role',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openPerson(context, credit),
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) tvEnsureVisible(context, alignment: 0.35);
        },
        focusColor: Colors.transparent,
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _focused ? MarqueeColors.boothRaised : null,
            borderRadius: const BorderRadius.all(MarqueeRadius.card),
            border: _focused
                ? Border.all(color: MarqueeColors.bulb, width: 2)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 82,
              child: Column(
                children: [
                  PersonPhoto(
                    name: credit.name,
                    imageUrl: credit.imageUrl,
                    size: 70,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    credit.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption
                        .copyWith(
                          color: _focused
                              ? MarqueeColors.bulb
                              : MarqueeColors.cream,
                        )
                        .withWeight(FontWeight.w600),
                  ),
                  if (role.isNotEmpty)
                    Text(role, style: text.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvMoreLikeThis extends ConsumerWidget {
  const _TvMoreLikeThis({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(recommendationsProvider(id));
    return TvMediaRow(
      title: AppLocalizations.of(context).moreLikeThis,
      items: recs.value ?? const [],
      loading: recs.isLoading,
      error: recs.hasError ? recs.error : null,
      onRetry: () => ref.invalidate(recommendationsProvider(id)),
    );
  }
}

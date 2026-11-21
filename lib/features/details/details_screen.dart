import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/catalog_providers.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/bulb_loader.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/media_image.dart';
import '../../app/widgets/media_row.dart';
import '../../app/widgets/media_text.dart';
import '../../app/widgets/word_fit_title.dart';
import '../../app/widgets/sub_page.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import '../../data/repositories/library_repository.dart';
import '../downloads/download_actions.dart';
import '../library/widgets/favorite_button.dart';
import 'details_providers.dart';
import 'play_target.dart';
import 'widgets/credits_row.dart';
import 'widgets/episode_list.dart';

/// From this content width the details header puts the text beside a large
/// poster (the desktop two-column layout).
const _wideHeader = 900.0;

/// A title's page, pushed inside the current tab (DESIGN.md §8): poster,
/// title and metadata, Play and Trailer, synopsis, genres, episodes for a
/// series, cast and crew, and "More like this".
///
/// [args] (what the list showed) lets the header draw at once; the full
/// record loads behind it.
class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.id, this.args});

  final String id;
  final TitleArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final details = ref.watch(detailsProvider(id));
    final record = details.value;
    final item = record?.item ?? args?.item;

    Widget page(Widget body) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                gutter - 4,
                MarqueeSpace.m,
                gutter,
                0,
              ),
              child: const BackPill(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );

    if (item == null) {
      if (details.hasError) {
        return page(
          ErrorView(
            error: details.error!,
            onRetry: () => ref.invalidate(detailsProvider(id)),
          ),
        );
      }
      if (details.isLoading) {
        return page(Center(child: BulbLoader(semanticLabel: l10n.loading)));
      }
      return page(
        Center(
          child: Text(
            l10n.titleUnavailable,
            style: MarqueeText.of(context).body,
          ),
        ),
      );
    }

    return page(
      ListView(
        padding: const EdgeInsetsDirectional.only(bottom: MarqueeSpace.huge),
        children: [
          _Header(item: item, details: record, gutter: gutter),
          if (record == null && details.hasError)
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                gutter,
                MarqueeSpace.l,
                gutter,
                0,
              ),
              child: ErrorView(
                error: details.error!,
                onRetry: () => ref.invalidate(detailsProvider(id)),
                compact: true,
              ),
            ),
          if (item.isSeries)
            EpisodeList(
              seriesId: item.seriesId,
              gutter: gutter,
              onPlay: (episode) => openPlayer(
                context,
                PlaybackRequest(item: item, episode: episode),
              ),
              initialSeason: args?.item.rootSeriesId != null
                  ? args?.item.season
                  : null,
              trailing: (episode) =>
                  EpisodeDownloadButton(series: item, episode: episode),
              seasonAction: (season) =>
                  SeasonDownloadButton(series: item, season: season),
            ),
          if (record != null) CreditsRow(details: record, gutter: gutter),
          _MoreLikeThis(id: id),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.item,
    required this.details,
    required this.gutter,
  });

  final MediaItem item;
  final MediaDetails? details;
  final double gutter;

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

    final titleBlock = <Widget>[
      // A long word steps the size down instead of breaking in half.
      WordFitTitle(
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
            onPressed: () => _open(external),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 36),
            ),
            // Anime links go to MyAnimeList (PLAN.md §4.1).
            child: Text(details!.imdbUrlIsImdb ? 'IMDb' : 'MyAnimeList'),
          ),
        ),
    ];

    final actions = Wrap(
      spacing: MarqueeSpace.m,
      runSpacing: MarqueeSpace.m,
      children: [
        _PlayButton(item: item),
        FavoritePill(item: item),
        if (!item.isSeries) DownloadPill(item: item),
        if (trailer != null)
          OutlinedButton.icon(
            onPressed: () => _open(trailer),
            icon: const Icon(Icons.smart_display_outlined, size: 18),
            label: Text(l10n.trailer),
          ),
      ],
    );

    final description = item.description.resolve(arabic: arabic);
    final extras = <Widget>[
      const SizedBox(height: MarqueeSpace.l),
      actions,
      if (description != null && description.isNotEmpty) ...[
        const SizedBox(height: MarqueeSpace.l),
        _Synopsis(description),
      ],
      _GenreChips(item: item),
    ];

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        MarqueeSpace.m,
        gutter,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _wideHeader;
          final posterWidth = wide ? 220.0 : 128.0;
          final poster = SizedBox(
            width: posterWidth,
            height: posterWidth * 1.5,
            child: MediaImage(
              url: item.hdPosterUrl ?? item.posterUrl,
              borderRadius: const BorderRadius.all(MarqueeRadius.poster),
            ),
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                poster,
                const SizedBox(width: MarqueeSpace.xxxl),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [...titleBlock, ...extras],
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The poster at the top: a long title grows downwards beside
              // it instead of pushing it down.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  const SizedBox(width: MarqueeSpace.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: titleBlock,
                    ),
                  ),
                ],
              ),
              ...extras,
            ],
          );
        },
      ),
    );
  }
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The synopsis, four lines until expanded.
class _Synopsis extends StatefulWidget {
  const _Synopsis(this.text);

  final String text;

  @override
  State<_Synopsis> createState() => _SynopsisState();
}

class _SynopsisState extends State<_Synopsis> {
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

/// The title's genres as pills; each opens its genre page. The API sends
/// genre names without IDs, so they are matched to the genre list by name.
class _GenreChips extends ConsumerWidget {
  const _GenreChips({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arabic = context.isArabicUi;
    final text = MarqueeText.of(context);
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
          (name, match(c.en, c.ar)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.m),
      child: Wrap(
        spacing: MarqueeSpace.s,
        runSpacing: MarqueeSpace.s,
        children: [
          for (final (name, genre) in chips)
            Material(
              color: Colors.transparent,
              shape: const StadiumBorder(
                side: BorderSide(color: MarqueeColors.velvet),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: genre == null ? null : () => openGenre(context, genre),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Text(
                    name,
                    style: text.label
                        .copyWith(fontSize: 13)
                        .withWeight(FontWeight.w500),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreLikeThis extends ConsumerWidget {
  const _MoreLikeThis({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(recommendationsProvider(id));
    return MediaRow(
      title: AppLocalizations.of(context).moreLikeThis,
      items: recs.value ?? const [],
      loading: recs.isLoading,
      error: recs.hasError ? recs.error : null,
      onRetry: () => ref.invalidate(recommendationsProvider(id)),
    );
  }
}

/// Play, or where to pick up (DESIGN.md §8): "Resume · 14 min left" for a
/// movie, "Resume · S2 E5 · 14 min left" for a series, or "Play · S2 E6"
/// after a finished episode (PLAYER.md §7.6).
class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final target = item.isSeries
        ? playTarget(
            item,
            watched:
                ref.watch(seriesProgressProvider(item.seriesId)).value ??
                const {},
            episodes:
                ref.watch(episodesProvider(item.seriesId)).value ??
                const <Episode>[],
          )
        : playTarget(
            item,
            saved: ref.watch(watchProgressProvider(item.id)).value,
          );
    final request = target.request;
    final episode = target.episode;
    final label = [
      if (target.resume) l10n.resume else l10n.play,
      if (episode != null)
        l10n.seasonEpisodeShort(episode.season, episode.episode),
      if (target.left case final left?) minutesLeft(l10n, left),
    ].join(' · ');

    return FilledButton.icon(
      onPressed: () => openPlayer(context, request),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(label),
    );
  }
}

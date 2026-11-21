import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation_args.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/error_view.dart';
import '../../../app/widgets/media_text.dart';
import '../../../core/platform/platform_info.dart';
import '../../../data/models/media_details.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/playback_models.dart';
import '../../../data/models/watch_progress.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../features/details/details_providers.dart';
import '../../../features/details/episode_view.dart';
import '../../../features/details/play_target.dart';
import '../../focus/tv_focusable.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_downloads.dart';
import '../../widgets/tv_focus_look.dart';
import '../../widgets/tv_image.dart';
import '../../widgets/tv_row.dart';
import 'tv_episodes.dart';

/// Whether a link can open on this TV (a trailer needs the YouTube app):
/// Trailer is hidden when nothing can (docs/TV.md §7.3).
final _canOpenProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  url,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await canLaunchUrl(uri);
  } on Object {
    return false;
  }
});

/// A title's page on TV (docs/TV.md §7.3, the TV Details design): the
/// poster beside the title, meta, synopsis and the actions (zone 0, where
/// focus starts on Play or Resume); for a series the episodes (zone 1);
/// Cast and crew (2) and More like this (3).
///
/// Genres are in the meta line, not focusable (one zone less), and there's
/// no IMDb link: TVs have no browser. A series' Download in the actions
/// downloads the season shown below.
class TvDetailsScreen extends ConsumerStatefulWidget {
  const TvDetailsScreen({super.key, required this.id, this.args});

  final String id;
  final TitleArgs? args;

  @override
  ConsumerState<TvDetailsScreen> createState() => _TvDetailsScreenState();
}

class _TvDetailsScreenState extends ConsumerState<TvDetailsScreen> {
  int? _season;
  int? _block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final details = ref.watch(detailsProvider(widget.id));
    final record = details.value;
    final item = record?.item ?? widget.args?.item;

    if (item == null) {
      return TvScreen(
        order: 1,
        builder: (context, scroll) => Center(
          child: details.isLoading
              ? BulbLoader(semanticLabel: l10n.loading)
              : _Problem(
                  message: details.hasError
                      ? errorMessage(l10n, details.error!)
                      : l10n.titleUnavailable,
                  onRetry: details.hasError
                      ? () => ref.invalidate(detailsProvider(widget.id))
                      : null,
                ),
        ),
      );
    }

    final all = item.isSeries
        ? ref.watch(episodesProvider(item.seriesId)).value ?? const <Episode>[]
        : const <Episode>[];
    final watched = item.isSeries
        ? ref.watch(seriesProgressProvider(item.seriesId)).value ?? const {}
        : const <String, WatchProgress>{};
    // Opening an episode (from Continue watching) opens on its season.
    final args = widget.args?.item;
    final view = all.isEmpty
        ? null
        : EpisodeView(
            all,
            watched,
            initialSeason: args?.rootSeriesId != null ? args?.season : null,
            season: _season,
            block: _block,
          );

    return TvScreen(
      order: 1,
      // A section heading sits just above its zone's top.
      keylineTop: TvSpace.pageKeyline + 4,
      builder: (context, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.only(
          top: TvSpace.safeV,
          bottom: TvSpace.safeV,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              item: item,
              details: record,
              seasons: view?.seasons.length,
              actions: _Actions(item: item, details: record),
            ),
            if (record == null && details.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TvSpace.safeH,
                  16,
                  TvSpace.safeH,
                  0,
                ),
                child: Text(
                  errorMessage(l10n, details.error!),
                  style: text.body.copyWith(color: context.palette.dust),
                ),
              ),
            if (view != null) ...[
              const SizedBox(height: 28),
              TvEpisodes(
                order: 1,
                series: item,
                all: all,
                view: view,
                watched: watched,
                downloads: supportsDownloads,
                onSelect: (season, block) {
                  if (season == view.season && block == view.block) return;
                  setState(() {
                    _season = season;
                    _block = block;
                  });
                },
              ),
            ],
            if (record != null) _Cast(order: 2, details: record),
            _MoreLikeThis(order: 3, id: widget.id),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.details,
    required this.seasons,
    required this.actions,
  });

  final MediaItem item;
  final MediaDetails? details;
  final int? seasons;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final arabic = context.isArabicUi;
    final title = context.titleOf(item);
    final audio = [
      for (final l in details?.audioLanguages ?? const [])
        ?l.resolve(arabic: arabic),
    ].join(', ');
    final meta = context.joinMeta(
      [
        if (item.year != null) '${item.year}',
        ...item.categories.take(3).map((c) => c.resolve(arabic: arabic) ?? ''),
        if (!item.isSeries && item.duration != null)
          formatDuration(l10n, item.duration!),
        if (item.isSeries && seasons != null) l10n.seasonCount(seasons!),
        if (audio.isNotEmpty) l10n.audioLanguages(audio),
      ].where((s) => s.isNotEmpty),
    );
    final synopsis = item.description.resolve(arabic: arabic) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            height: 225,
            child: TvImage(
              url: item.posterUrl,
              hdUrl: item.hdPosterUrl,
              radius: 10,
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MarqueeText.hasArabic(title) ? title : title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.displayLargeFor(title),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(meta, style: text.caption),
                ],
                if (synopsis.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Text(
                      synopsis,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.body,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                actions,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Play or Resume (primary), Download (a movie; a series downloads from its
/// episodes pane), Favorite, and Trailer when this TV can open it.
class _Actions extends ConsumerWidget {
  const _Actions({required this.item, required this.details});

  final MediaItem item;
  final MediaDetails? details;

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
    final episode = target.episode;
    final playLabel = context.joinMeta([
      if (target.resume) l10n.resume else l10n.play,
      if (episode != null)
        l10n.seasonEpisodeShort(episode.season, episode.episode),
      if (target.left case final left?) minutesLeft(l10n, left),
    ]);
    final saved = ref.watch(isFavoriteProvider(item.seriesId)).value ?? false;
    final trailer = details?.trailerUrl;
    final canTrailer =
        trailer != null &&
        (ref.watch(_canOpenProvider(trailer)).value ?? false);
    return TvZone.row(
      order: 0,
      initial: true,
      keyline: 0,
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        children: [
          TvButton(
            index: 0,
            primary: true,
            icon: Icons.play_arrow_rounded,
            label: playLabel,
            onSelect: () => tvOpenPlayer(context, target.request),
          ),
          // A series downloads a season from the episodes pane.
          if (!item.isSeries && supportsDownloads)
            TvMovieDownloadButton(index: 1, item: item),
          TvButton(
            index: 2,
            icon: saved ? Icons.bookmark : Icons.bookmark_border,
            label: saved ? l10n.inFavorites : l10n.favorite,
            onSelect: () {
              final library = ref.read(libraryRepositoryProvider);
              saved
                  ? library.removeFavorite(item.seriesId)
                  : library.addFavorite(item);
            },
          ),
          if (canTrailer)
            TvButton(
              index: 3,
              icon: Icons.smart_display_outlined,
              label: l10n.trailer,
              onSelect: () => launchUrl(
                Uri.parse(trailer),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Cast and crew": round photos (or initials) with the name and role.
/// OK opens the person's page.
class _Cast extends StatelessWidget {
  const _Cast({required this.order, required this.details});

  final int order;
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
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvSectionTitle(l10n.castAndCrew),
          SizedBox(
            height: 22 + 96 + 10 + 44,
            child: TvZone.row(
              order: order,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.fromSTEB(
                  TvSpace.safeH,
                  22,
                  TvSpace.safeH,
                  0,
                ),
                itemExtent: 128,
                itemCount: people.length,
                itemBuilder: (context, i) => Align(
                  alignment: AlignmentDirectional.topStart,
                  child: TvPersonCard(index: i, credit: people[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A person in Cast and crew, item [index]: a 96 dp round photo (or their
/// initials), the name and the role. Focused, the photo grows with the ring.
class TvPersonCard extends StatelessWidget {
  const TvPersonCard({super.key, required this.index, required this.credit});

  final int index;
  final StaffCredit credit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final role = tvRoleLabel(l10n, credit.role);
    return TvFocusable(
      index: index,
      label: role.isEmpty ? credit.name : '${credit.name}, $role',
      onSelect: () => tvOpenPerson(context, credit),
      builder: (context, focused) => SizedBox(
        width: 110,
        child: Column(
          children: [
            SizedBox.square(
              dimension: 96,
              child: TvCardFocus(
                focused: focused,
                radius: 48,
                child: TvPersonPhoto(
                  name: credit.name,
                  url: credit.imageUrl,
                  size: 96,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              credit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: text.label
                  .withWeight(FontWeight.w500)
                  .copyWith(
                    height: 1.3,
                    color: focused
                        ? context.palette.cream
                        : context.palette.creamSoft,
                  ),
            ),
            if (role.isNotEmpty)
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.caption,
              ),
          ],
        ),
      ),
    );
  }
}

String tvRoleLabel(AppLocalizations l10n, StaffRole role) => switch (role) {
  StaffRole.actor => l10n.roleActor,
  StaffRole.director => l10n.roleDirector,
  StaffRole.writer => l10n.roleWriter,
  StaffRole.other => '',
};

/// A round photo, or the person's initials on `booth` when there's none.
class TvPersonPhoto extends StatelessWidget {
  const TvPersonPhoto({
    super.key,
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url != null) {
      return SizedBox.square(
        dimension: size,
        child: TvImage(url: url, radius: size / 2, grows: true),
      );
    }
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.booth,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: MarqueeTvText.of(context).sectionTitle
            .copyWith(fontSize: size * 0.32),
      ),
    );
  }
}

class _MoreLikeThis extends ConsumerWidget {
  const _MoreLikeThis({required this.order, required this.id});

  final int order;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recs = ref.watch(recommendationsProvider(id));
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: TvPosterRow(
        order: order,
        title: l10n.moreLikeThis,
        items: recs.value ?? const [],
        loading: recs.isLoading && !recs.hasValue,
        onOpen: (item) => tvOpenTitle(context, item),
      ),
    );
  }
}

/// A page that couldn't load: why, and Try again (or Back).
class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    return Padding(
      padding: TvSpace.safe,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center, style: text.body),
          const SizedBox(height: 24),
          TvZone.row(
            order: 0,
            initial: true,
            keyline: 0,
            child: TvButton(
              index: 0,
              primary: true,
              label: onRetry != null ? l10n.retry : l10n.tvBack,
              onSelect: onRetry ?? () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

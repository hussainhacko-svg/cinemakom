import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/catalog_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/widgets/media_text.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../data/models/catalog_models.dart';
import '../../../data/paging/media_sources.dart';
import '../../../features/genre/genre_providers.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_chip.dart';
import '../../widgets/tv_choice_panel.dart';
import '../../widgets/tv_paged_grid.dart';

/// A genre on TV (docs/TV.md §7.2, the TV Genre design): its name, then on
/// the same line the Sort · Kind · Audio chips (zone 0, each opens a choice
/// panel), and the infinitely paged grid (zone 1, where focus starts).
class TvGenreScreen extends ConsumerStatefulWidget {
  const TvGenreScreen({super.key, required this.categoryId, this.genre});

  final String categoryId;

  /// The genre as the list showed it; looked up by ID when missing.
  final Category? genre;

  @override
  ConsumerState<TvGenreScreen> createState() => _TvGenreScreenState();
}

class _TvGenreScreenState extends ConsumerState<TvGenreScreen> {
  VideoKind _kind = VideoKind.movies;
  SortOrder _sort = SortOrder.recentlyAdded;
  String? _languageId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final arabic = context.isArabicUi;
    final genre =
        widget.genre ??
        ref
            .watch(genresProvider)
            .value
            ?.where((g) => g.id == widget.categoryId)
            .firstOrNull;
    final title = genre?.name.resolve(arabic: arabic) ?? '';
    final languages = ref.watch(
      genreLanguagesProvider((widget.categoryId, _kind)),
    );
    // A chosen language this kind doesn't have falls back to all.
    final language = languages
        .where((l) => l.languageId == _languageId)
        .firstOrNull;
    final source = GenreSource(
      categoryId: widget.categoryId,
      kind: _kind,
      sort: _sort,
      languageId: language?.languageId,
    );
    String kindLabel(VideoKind k) =>
        k == VideoKind.series ? l10n.kindSeries : l10n.kindMovies;

    return TvScreen(
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                TvSpace.safeH,
                TvSpace.safeV,
                TvSpace.safeH,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      arabic ? title : title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.displayLargeFor(title),
                    ),
                  ),
                  const SizedBox(width: 24),
                  TvZone.row(
                    order: 0,
                    keyline: 0,
                    child: Row(
                      children: [
                        TvChip(
                          index: 0,
                          name: l10n.sortTitle,
                          label: sortOrderLabel(l10n, _sort),
                          onSelect: () async {
                            final sort = await showTvChoicePanel<SortOrder>(
                              context,
                              title: l10n.sortTitle,
                              selected: _sort,
                              choices: [
                                for (final s in SortOrder.values)
                                  TvChoice(s, sortOrderLabel(l10n, s)),
                              ],
                            );
                            if (sort != null) setState(() => _sort = sort);
                          },
                        ),
                        const SizedBox(width: 12),
                        TvChip(
                          index: 1,
                          name: l10n.tvFilterKind,
                          label: kindLabel(_kind),
                          onSelect: () async {
                            final kind = await showTvChoicePanel<VideoKind>(
                              context,
                              title: l10n.tvFilterKind,
                              selected: _kind,
                              choices: [
                                for (final k in [
                                  VideoKind.movies,
                                  VideoKind.series,
                                ])
                                  TvChoice(k, kindLabel(k)),
                              ],
                            );
                            if (kind != null) setState(() => _kind = kind);
                          },
                        ),
                        if (languages.length > 1) ...[
                          const SizedBox(width: 12),
                          TvChip(
                            index: 2,
                            name: l10n.tvFilterAudio,
                            label:
                                language?.name.resolve(arabic: arabic) ??
                                l10n.allLanguages,
                            onSelect: () async {
                              final picked = await showTvChoicePanel<String>(
                                context,
                                title: l10n.tvFilterAudio,
                                selected: language?.languageId ?? '',
                                choices: [
                                  TvChoice('', l10n.allLanguages),
                                  for (final l in languages)
                                    TvChoice(
                                      l.languageId,
                                      l.name.resolve(arabic: arabic) ?? '',
                                    ),
                                ],
                              );
                              if (picked != null) {
                                setState(
                                  () => _languageId = picked.isEmpty
                                      ? null
                                      : picked,
                                );
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          TvPagedGrid(
            key: ValueKey(source),
            order: 1,
            source: source,
            initial: true,
            onOpen: (item) => tvOpenTitle(context, item),
          ),
        ],
      ),
    );
  }
}

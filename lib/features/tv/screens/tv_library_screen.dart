import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../data/repositories/library_repository.dart';
import '../../library/library_providers.dart';
import '../../library/widgets/continue_card.dart' show playContinue;
import '../tv_shell.dart' show tvGutter;
import '../widgets/tv_continue_card.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_paged_grid.dart';

enum _Shelf { continueWatching, favorites }

/// Dedicated 10-foot Android TV Library tab: Continue watching | Favorites
/// pills, continue cards with sibling Play and Remove buttons, and an HD
/// favorites poster grid.
class TvLibraryScreen extends ConsumerStatefulWidget {
  const TvLibraryScreen({super.key});

  @override
  ConsumerState<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends ConsumerState<TvLibraryScreen> {
  _Shelf _shelf = _Shelf.continueWatching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(libraryRefreshProvider);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvPageHeader(title: l10n.navLibrary),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              tvGutter,
              0,
              tvGutter,
              MarqueeSpace.l,
            ),
            child: TvSegmented(
              segments: [
                (_Shelf.continueWatching, l10n.rowContinueWatching),
                (_Shelf.favorites, l10n.libraryFavorites),
              ],
              selected: _shelf,
              onChanged: (s) => setState(() => _shelf = s),
            ),
          ),
          Expanded(
            child: switch (_shelf) {
              _Shelf.continueWatching => const _ContinueList(),
              _Shelf.favorites => const _Favorites(),
            },
          ),
        ],
      ),
    );
  }
}

class _ContinueList extends ConsumerWidget {
  const _ContinueList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(continueEntriesProvider).value;
    if (entries == null) return const SizedBox.shrink();
    if (entries.isEmpty) return _Empty(l10n.continueEmpty);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            tvGutter,
            0,
            tvGutter,
            MarqueeSpace.huge,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 520,
              mainAxisExtent: 104,
              crossAxisSpacing: MarqueeSpace.m,
              mainAxisSpacing: MarqueeSpace.m,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              return TvContinueCard(
                entry: entry,
                onTap: () => openTitle(context, entry.progress.item),
                trailing: IconButton(
                  tooltip: l10n.play,
                  onPressed: () => playContinue(context, entry),
                  style: IconButton.styleFrom(
                    backgroundColor: MarqueeColors.boothRaised,
                    side: const BorderSide(color: MarqueeColors.velvetStrong),
                    fixedSize: const Size.square(44),
                  ),
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    size: 22,
                    color: MarqueeColors.bulb,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Favorites extends ConsumerWidget {
  const _Favorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(favoritesProvider).value;
    if (items == null) return const SizedBox.shrink();
    if (items.isEmpty) {
      return _Empty(AppLocalizations.of(context).favoritesEmpty);
    }
    return CustomScrollView(
      slivers: [
        TvPosterGridSliver(items: items),
        const SliverToBoxAdapter(child: SizedBox(height: MarqueeSpace.huge)),
      ],
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

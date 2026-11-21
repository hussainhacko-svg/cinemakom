import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/controls.dart';
import '../../app/widgets/paged_grid.dart';
import '../../app/widgets/tab_page.dart';
import '../../data/repositories/library_repository.dart';
import 'library_providers.dart';
import 'widgets/continue_card.dart';

enum _Shelf { continueWatching, favorites }

/// The Library tab (DESIGN.md §8): a [Continue watching | Favorites]
/// segmented control over the continue cards or the favorites' poster grid.
/// Opening it refreshes the stored titles once per session.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _Shelf _shelf = _Shelf.continueWatching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    ref.watch(libraryRefreshProvider);
    return TabPage(
      title: l10n.navLibrary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              gutter,
              0,
              gutter,
              MarqueeSpace.l,
            ),
            // Shrinks only when the labels don't fit (large text sizes).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Segmented(
                segments: [
                  (_Shelf.continueWatching, l10n.rowContinueWatching),
                  (_Shelf.favorites, l10n.libraryFavorites),
                ],
                selected: _shelf,
                onChanged: (s) => setState(() => _shelf = s),
              ),
            ),
          ),
          Expanded(
            child: switch (_shelf) {
              _Shelf.continueWatching => _ContinueList(gutter: gutter),
              _Shelf.favorites => _Favorites(gutter: gutter),
            },
          ),
        ],
      ),
    );
  }
}

/// Continue cards, full width on phones and in columns of about 560 dp on
/// wide windows. A card opens the title; its play button plays.
class _ContinueList extends ConsumerWidget {
  const _ContinueList({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(continueEntriesProvider).value;
    // The database answers at once: no loader for a frame.
    if (entries == null) return const SizedBox.shrink();
    if (entries.isEmpty) return _Empty(l10n.continueEmpty);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(
            gutter,
            0,
            gutter,
            MarqueeSpace.huge,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 560,
              mainAxisExtent: 100,
              crossAxisSpacing: MarqueeSpace.m,
              mainAxisSpacing: MarqueeSpace.m,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              return ContinueCard(
                entry: entry,
                onTap: () => openTitle(context, entry.progress.item),
                trailing: IconButton(
                  tooltip: l10n.play,
                  onPressed: () => playContinue(context, entry),
                  style: IconButton.styleFrom(
                    backgroundColor: context.palette.boothRaised,
                    side: BorderSide(color: context.palette.velvetStrong),
                    fixedSize: const Size.square(44),
                  ),
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    size: 22,
                    color: context.palette.bulb,
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

/// The favorites as a poster grid, the last added first.
class _Favorites extends ConsumerWidget {
  const _Favorites({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(favoritesProvider).value;
    if (items == null) return const SizedBox.shrink();
    if (items.isEmpty) {
      return _Empty(AppLocalizations.of(context).favoritesEmpty);
    }
    return CustomScrollView(
      slivers: [
        PosterGridSliver(items: items, gutter: gutter),
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

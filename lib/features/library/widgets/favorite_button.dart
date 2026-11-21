import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../data/models/media_item.dart';
import '../../../data/repositories/library_repository.dart';

/// Adds [item]'s movie or series to Favorites, or takes it out.
void _toggle(WidgetRef ref, MediaItem item, {required bool saved}) {
  final library = ref.read(libraryRepositoryProvider);
  saved ? library.removeFavorite(item.seriesId) : library.addFavorite(item);
}

bool _isSaved(WidgetRef ref, MediaItem item) =>
    ref.watch(isFavoriteProvider(item.seriesId)).value ?? false;

/// Details' Favorite button (DESIGN.md §8): a secondary pill with a
/// bookmark, "Favorite", or "In favorites" with the bookmark filled.
class FavoritePill extends ConsumerWidget {
  const FavoritePill({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = _isSaved(ref, item);
    return Semantics(
      toggled: saved,
      child: OutlinedButton.icon(
        onPressed: () => _toggle(ref, item, saved: saved),
        icon: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: 18,
          color: saved ? context.palette.bulb : null,
        ),
        label: Text(saved ? l10n.inFavorites : l10n.favorite),
      ),
    );
  }
}

/// The hero's Favorite icon button (DESIGN.md §5): a 44 px circle, `booth`
/// fill and `velvet` border, with the bookmark filled in `bulb` once saved.
class FavoriteIconButton extends ConsumerWidget {
  const FavoriteIconButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = _isSaved(ref, item);
    return IconButton(
      tooltip: saved ? l10n.removeFromFavorites : l10n.addToFavorites,
      isSelected: saved,
      onPressed: () => _toggle(ref, item, saved: saved),
      style: IconButton.styleFrom(
        backgroundColor: context.palette.booth,
        side: BorderSide(color: context.palette.velvet),
        fixedSize: const Size.square(44),
      ),
      icon: const Icon(Icons.bookmark_border_rounded, size: 20),
      selectedIcon: Icon(
        Icons.bookmark_rounded,
        size: 20,
        color: context.palette.bulb,
      ),
    );
  }
}

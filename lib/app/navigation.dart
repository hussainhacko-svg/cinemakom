import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models/catalog_models.dart';
import '../data/models/media_item.dart';
import '../data/paging/media_sources.dart';

/// What the "See all" screen shows.
class MediaListArgs {
  const MediaListArgs({required this.title, required this.source});

  final String title;
  final MediaSource source;
}

/// What the details screen opens on. [item] is what the list showed, so the
/// header can draw before the full record arrives; a later episode of a
/// series preselects its season.
class TitleArgs {
  const TitleArgs(this.item);

  final MediaItem item;
}

/// Pages opened from a list stay inside the tab they were opened from, so
/// the navigation stays visible and back returns to the list (DESIGN.md §8).
String _tabRoot(BuildContext context) =>
    '/${GoRouterState.of(context).uri.pathSegments.first}';

/// Opens [item]'s details. Episodes open their series.
void openTitle(BuildContext context, MediaItem item) => context.push(
  '${_tabRoot(context)}/title/${item.seriesId}',
  extra: TitleArgs(item),
);

void openGenre(BuildContext context, Category genre) =>
    context.push('${_tabRoot(context)}/genre/${genre.id}', extra: genre);

void openList(BuildContext context, MediaListArgs args) =>
    context.push('${_tabRoot(context)}/list', extra: args);

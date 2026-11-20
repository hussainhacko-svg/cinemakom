import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models/catalog_models.dart';
import '../data/models/media_details.dart';
import '../data/models/media_item.dart';
import '../data/models/playback_request.dart';
import 'navigation_args.dart';

export 'navigation_args.dart';

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

/// Opens an actor's, director's or writer's page: their titles.
void openPerson(BuildContext context, StaffCredit credit) => context.push(
  '${_tabRoot(context)}/person/${credit.id}',
  extra: PersonArgs(credit),
);

void openList(BuildContext context, MediaListArgs args) =>
    context.push('${_tabRoot(context)}/list', extra: args);

/// Opens the full-screen player (outside the tabs, so the navigation bar is
/// hidden). Back returns to the page it was opened from.
void openPlayer(BuildContext context, PlaybackRequest request) =>
    context.push('/watch/${request.videoId}', extra: request);

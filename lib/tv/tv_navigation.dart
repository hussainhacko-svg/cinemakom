import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app/navigation_args.dart';
import '../data/models/catalog_models.dart';
import '../data/models/media_item.dart';
import '../data/models/playback_request.dart';

// Opening pages on TV (docs/TV.md §4.4): the phone's paths and arguments.
// Pages push inside the current tab; the player pushes above the shell.
// Focus comes back to the item that opened a page when it pops (R2: the
// screen remembers where it was).

String _tabRoot(BuildContext context) =>
    '/${GoRouterState.of(context).uri.pathSegments.first}';

/// [item]'s details; an episode opens its series.
void tvOpenTitle(BuildContext context, MediaItem item) => context.push(
  '${_tabRoot(context)}/title/${item.seriesId}',
  extra: TitleArgs(item),
);

void tvOpenGenre(BuildContext context, Category genre) =>
    context.push('${_tabRoot(context)}/genre/${genre.id}', extra: genre);

/// "See all".
void tvOpenList(BuildContext context, MediaListArgs args) =>
    context.push('${_tabRoot(context)}/list', extra: args);

void tvOpenPlayer(BuildContext context, PlaybackRequest request) =>
    context.push('/watch/${request.videoId}', extra: request);

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_ui/material_ui.dart';

import '../../../app/navigation_args.dart';
import '../../focus/tv_screen.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_paged_grid.dart';

/// "See all" on TV: the list's name and its titles as a paged grid. Focus
/// starts on the first poster.
class TvListScreen extends StatelessWidget {
  const TvListScreen({super.key, required this.args});

  final MediaListArgs args;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
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
              child: Text(
                text.arabic ? args.title : args.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.displayLargeFor(args.title),
              ),
            ),
          ),
          TvPagedGrid(
            order: 0,
            source: args.source,
            initial: true,
            onOpen: (item) => tvOpenTitle(context, item),
          ),
        ],
      ),
    );
  }
}

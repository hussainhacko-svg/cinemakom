import 'package:material_ui/material_ui.dart';

import '../../../app/navigation.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_paged_grid.dart';

/// Dedicated 10-foot Android TV "See all" list screen: title header + HD
/// infinitely scrolling poster grid with initial focus on the first poster.
class TvMediaListScreen extends StatelessWidget {
  const TvMediaListScreen({super.key, required this.args});

  final MediaListArgs args;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: TvPageHeader(title: args.title)),
        TvPagedGridSlivers(source: args.source, autofocusFirst: true),
      ],
    ),
  );
}

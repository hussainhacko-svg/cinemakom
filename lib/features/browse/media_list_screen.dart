import 'package:material_ui/material_ui.dart';

import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/paged_grid.dart';
import '../../app/widgets/sub_page.dart';

/// "See all" for a Home row: the row's whole list, infinitely scrolling.
/// No sort control: the catalog ignores title sorts, and the other lists
/// have a fixed order (PLAN.md §4.1).
class MediaListScreen extends StatelessWidget {
  const MediaListScreen({super.key, required this.args});

  final MediaListArgs args;

  @override
  Widget build(BuildContext context) {
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SubPageHeader(title: args.title, gutter: gutter),
            PagedGridSlivers(source: args.source, gutter: gutter),
          ],
        ),
      ),
    );
  }
}

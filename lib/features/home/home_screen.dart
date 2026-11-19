import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/shell/app_shell.dart';
import '../../app/widgets/tab_page.dart';

/// Home. On phones it opens with the logo lockup instead of a title
/// (DESIGN.md §8); with a rail, the rail already carries the brand, so the
/// page starts straight with its content. The rows arrive in Phase 3.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final withBar =
        navLayoutFor(MediaQuery.sizeOf(context).width) == NavLayout.bar;
    return TabPage(
      header: withBar
          ? const Align(
              alignment: AlignmentDirectional.centerStart,
              child: CinemakomLogo(markSize: 36),
            )
          : const SizedBox.shrink(),
    );
  }
}

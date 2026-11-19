import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/widgets/tab_page.dart';

/// Library: Continue watching and Favorites. Built in Phase 5.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      TabPage(title: AppLocalizations.of(context).navLibrary);
}

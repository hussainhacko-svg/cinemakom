import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/widgets/tab_page.dart';

/// Downloads. Built in Phase 6.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      TabPage(title: AppLocalizations.of(context).navDownloads);
}

import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/widgets/tab_page.dart';

/// Search. The field, genre grid and results arrive in Phase 3.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      TabPage(title: AppLocalizations.of(context).navSearch);
}

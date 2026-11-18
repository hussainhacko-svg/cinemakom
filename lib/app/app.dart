import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import '../features/debug/debug_screen.dart';
import 'l10n/app_localizations.dart';
import 'theme/marquee_theme.dart';

class CinemakomApp extends StatelessWidget {
  const CinemakomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      // English is the default. Phase 2 adds the first-launch language picker
      // and stores the choice; Arabic switches the layout to RTL.
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // The one and only theme (docs/DESIGN.md).
      theme: buildMarqueeTheme(arabic: false),
      home: const _PlaceholderScreen(),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          // Developer-only API check; removed from release builds.
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DebugScreen()),
              ),
            ),
        ],
      ),
      body: Center(child: Text(l10n.setupPlaceholder)),
    );
  }
}

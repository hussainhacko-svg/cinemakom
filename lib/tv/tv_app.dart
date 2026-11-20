import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import '../app/brand/cinemakom_mark.dart';
import '../app/l10n/app_localizations.dart';
import '../app/theme/marquee_colors.dart';
import '../app/theme/marquee_theme.dart';
import 'tv_keys.dart';

/// The TV app's root (docs/TV.md §4.1), chosen in `main` when `useTvUi`.
///
/// TV-0 placeholder: it proves the TV entry, the landscape start and the
/// remote's keys, and shows the numbers §9.1 needs (the UI size and the pixel
/// ratio). The router, the TV theme and the language step come in TV-1/TV-2.
class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildMarqueeTheme(arabic: false),
      shortcuts: tvShortcuts,
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatefulWidget {
  const _Placeholder();

  @override
  State<_Placeholder> createState() => _PlaceholderState();
}

class _PlaceholderState extends State<_Placeholder> {
  String _lastKey = '–';

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      setState(
        () => _lastKey = event.logicalKey.keyLabel.isEmpty
            ? event.logicalKey.debugName ?? '?'
            : event.logicalKey.keyLabel,
      );
    }
    return false; // Only watching: the key still goes to the shortcuts.
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final size = media.size;
    final ratio = media.devicePixelRatio;
    String n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    return Actions(
      actions: {
        TvBackIntent: CallbackAction<TvBackIntent>(
          onInvoke: (_) => SystemNavigator.pop(),
        ),
      },
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CinemakomLogo(markSize: 64),
              const SizedBox(height: 32),
              Text(l10n.tvPlaceholder, style: theme.bodyLarge),
              const SizedBox(height: 16),
              // Technical readout for docs/TV.md §9.1, not translated.
              Text(
                '${n(size.width)} × ${n(size.height)} dp · ${n(ratio)}× · '
                '${n(size.width * ratio)} × ${n(size.height * ratio)} px',
                textDirection: TextDirection.ltr,
                style: theme.bodyMedium?.copyWith(color: MarqueeColors.dust),
              ),
              Text(
                l10n.tvLastKey(_lastKey),
                style: theme.bodyMedium?.copyWith(color: MarqueeColors.dust),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final i in [1, 2, 3])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: FilledButton(
                        autofocus: i == 1,
                        onPressed: () => setState(() => _lastKey = 'OK $i'),
                        child: Text('$i'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

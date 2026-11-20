import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import '../app/brand/cinemakom_mark.dart';
import '../app/l10n/app_localizations.dart';
import '../app/theme/marquee_colors.dart';
import 'focus/tv_back.dart';
import 'focus/tv_focus_watchdog.dart';
import 'focus/tv_screen.dart';
import 'focus/tv_zone.dart';
import 'theme/tv_space.dart';
import 'theme/tv_text.dart';
import 'tv_keys.dart';
import 'widgets/tv_button.dart';
import 'widgets/tv_choice_panel.dart';

/// The TV app's root (docs/TV.md §4.1), chosen in `main` when `useTvUi`:
/// the TV theme, the remote's keys (`tvShortcuts`), the Back ladder and, in
/// debug builds, the focus watchdog.
///
/// Until TV-2 it opens a placeholder built on the focus system (TV-1), with
/// the numbers §9.1 needed and a language panel to try RTL on the TV.
class TvApp extends StatefulWidget {
  const TvApp({super.key});

  @override
  State<TvApp> createState() => _TvAppState();
}

class _TvAppState extends State<TvApp> {
  Locale _locale = const Locale('en');

  @override
  Widget build(BuildContext context) {
    final arabic = _locale.languageCode == 'ar';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildMarqueeTvTheme(arabic: arabic),
      shortcuts: tvShortcuts,
      actions: {
        ...WidgetsApp.defaultActions,
        TvBackIntent: CallbackAction<TvBackIntent>(
          onInvoke: (_) => tvHandleBack(),
        ),
      },
      builder: (context, child) => TvFocusWatchdog(child: child!),
      home: _Placeholder(
        locale: _locale,
        onLocale: (l) => setState(() => _locale = l),
      ),
    );
  }
}

class _Placeholder extends StatefulWidget {
  const _Placeholder({required this.locale, required this.onLocale});

  final Locale locale;
  final ValueChanged<Locale> onLocale;

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
    return false; // Only watching: the key still goes to the app.
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

  Future<void> _pickLanguage(AppLocalizations l10n) async {
    final picked = await showTvChoicePanel<String>(
      context,
      title: l10n.settingsLanguage,
      selected: widget.locale.languageCode,
      choices: [
        TvChoice('en', l10n.languageEnglish),
        TvChoice('ar', l10n.languageArabic),
      ],
    );
    if (picked != null) widget.onLocale(Locale(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final media = MediaQuery.of(context);
    final size = media.size;
    final ratio = media.devicePixelRatio;
    String n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    return Scaffold(
      body: TvScreen(
        builder: (context, scroll) => Center(
          child: Padding(
            padding: TvSpace.safe,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CinemakomLogo(markSize: 64),
                const SizedBox(height: 32),
                Text(l10n.tvPlaceholder, style: text.body),
                const SizedBox(height: 16),
                // Technical readout for docs/TV.md §9.1, not translated.
                Text(
                  '${n(size.width)} × ${n(size.height)} dp · ${n(ratio)}× · '
                  '${n(size.width * ratio)} × ${n(size.height * ratio)} px',
                  textDirection: TextDirection.ltr,
                  style: text.caption,
                ),
                Text(l10n.tvLastKey(_lastKey), style: text.caption),
                const SizedBox(height: 24),
                TvZone.row(
                  order: 0,
                  initial: true,
                  child: Wrap(
                    spacing: 16,
                    children: [
                      for (final i in [0, 1, 2])
                        TvButton(
                          index: i,
                          label: '${i + 1}',
                          primary: i == 0,
                          onSelect: () =>
                              setState(() => _lastKey = 'OK ${i + 1}'),
                        ),
                      TvButton(
                        index: 3,
                        label: l10n.settingsLanguage,
                        icon: Icons.translate,
                        onSelect: () => _pickLanguage(l10n),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: MarqueeColors.night,
    );
  }
}

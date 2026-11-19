import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/downloads/downloader.dart';
import '../core/platform/orientation.dart';
import '../core/storage/preferences.dart';
import '../data/repositories/downloads_repository.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'splash_screen.dart';
import 'theme/marquee_theme.dart';

const _localizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The root widget. Shows the splash until startup has finished, then the
/// router. The UI language (and with it the text direction) comes from the
/// settings, so changing it in Settings switches the whole app live.
class CinemakomApp extends ConsumerWidget {
  const CinemakomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupProvider);
    if (!startup.hasValue) {
      // Before the settings load, the language is unknown: follow the device.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        theme: buildMarqueeTheme(arabic: false),
        home: SplashScreen(
          onRetry: startup.hasError
              ? () => ref
                  ..invalidate(preferenceStoreProvider)
                  ..invalidate(appStartupProvider)
              : null,
        ),
      );
    }

    final language = ref.watch(
      settingsProvider.select((s) => s.effectiveLanguage),
    );
    return _BrowseOrientation(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        locale: language.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        // The one and only theme (docs/DESIGN.md). Arabic only drops tracking.
        theme: buildMarqueeTheme(arabic: language == AppLanguage.arabic),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) => _Downloads(child: child!),
      ),
    );
  }
}

/// Starts the downloads engine once (it catches up with downloads that ran
/// while the app was closed) and keeps its notification texts in the UI
/// language.
class _Downloads extends ConsumerStatefulWidget {
  const _Downloads({required this.child});

  final Widget child;

  @override
  ConsumerState<_Downloads> createState() => _DownloadsState();
}

class _DownloadsState extends ConsumerState<_Downloads> {
  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _locale) return;
    final first = _locale == null;
    _locale = locale;
    final l10n = AppLocalizations.of(context);
    final notices = DownloadNotices(
      running: l10n.noticeDownloading,
      complete: l10n.noticeDownloaded,
      failed: l10n.noticeFailed,
      paused: l10n.noticePaused,
    );
    final downloads = ref.read(downloadsRepositoryProvider);
    unawaited(first ? downloads.start(notices) : downloads.setNotices(notices));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Applies the Settings screen-rotation choice on start and when it changes
/// (DESIGN.md §8). The player sets landscape itself and restores this.
class _BrowseOrientation extends ConsumerStatefulWidget {
  const _BrowseOrientation({required this.child});

  final Widget child;

  @override
  ConsumerState<_BrowseOrientation> createState() => _BrowseOrientationState();
}

class _BrowseOrientationState extends ConsumerState<_BrowseOrientation> {
  @override
  void initState() {
    super.initState();
    setBrowseOrientation(ref.read(settingsProvider).screenRotation);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsProvider.select((s) => s.screenRotation),
      (_, rotation) => setBrowseOrientation(rotation),
    );
    return widget.child;
  }
}

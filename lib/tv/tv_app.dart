import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/l10n/app_localizations.dart';
import '../app/theme/marquee_colors.dart';
import '../app/widgets/bulb_loader.dart';
import '../app/widgets/error_view.dart';
import '../app/widgets/media_image.dart';
import '../core/storage/preferences.dart';
import '../data/repositories/downloads_repository.dart';
import '../features/downloads/download_flow.dart' show buildDownloadNotices;
import 'focus/key_log.dart';
import 'focus/tv_back.dart';
import 'focus/tv_focus_watchdog.dart';
import 'focus/tv_screen.dart';
import 'focus/tv_zone.dart';
import 'theme/tv_space.dart';
import 'theme/tv_text.dart';
import 'tv_keys.dart';
import 'tv_router.dart';
import 'widgets/tv_button.dart';
import 'widgets/tv_image.dart';

const _localizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final _actions = <Type, Action<Intent>>{
  ...WidgetsApp.defaultActions,
  TvBackIntent: CallbackAction<TvBackIntent>(onInvoke: (_) => tvHandleBack()),
  TvMediaIntent: CallbackAction<TvMediaIntent>(
    onInvoke: (intent) => TvMedia.handler?.call(intent.key),
  ),
};

/// The TV app's root (docs/TV.md §4.1), chosen in `main` when `useTvUi`:
/// its own router and screens on the same settings, database and providers
/// as the phone app (so switching UIs on one device keeps everything), the
/// TV type sizes, the remote's keys (`tvShortcuts`), the Back ladder and, in
/// debug builds, the focus watchdog.
class TvApp extends ConsumerStatefulWidget {
  const TvApp({super.key});

  @override
  ConsumerState<TvApp> createState() => _TvAppState();
}

/// The remote's Back comes as Android's system Back (`didPopRoute`), and the
/// app always says it handles Back itself, so Android never closes it on its
/// own: the ladder decides, and its last rung leaves the app. (It used to
/// come in twice, also as a key: from See all, the second one left the
/// app.) This observer is added before the router's, so it goes first.
class _TvAppState extends ConsumerState<TvApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemNavigator.setFrameworkHandlesBack(true);
    TvKeyLog.start();
  }

  @override
  void dispose() {
    TvKeyLog.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    tvHandleBack();
    return true;
  }

  bool _handlesBack(NavigationNotification _) {
    SystemNavigator.setFrameworkHandlesBack(true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(appStartupProvider);
    if (!startup.hasValue) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        theme: buildMarqueeTvTheme(arabic: false),
        shortcuts: tvShortcuts,
        actions: _actions,
        onNavigationNotification: _handlesBack,
        home: _Splash(
          error: startup.error,
          onRetry: () => ref
            ..invalidate(preferenceStoreProvider)
            ..invalidate(appStartupProvider),
        ),
      );
    }
    final language = ref.watch(
      settingsProvider.select((s) => s.effectiveLanguage),
    );
    final images = ref.watch(networkImagesProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: _localizationsDelegates,
      theme: buildMarqueeTvTheme(arabic: language == AppLanguage.arabic),
      shortcuts: tvShortcuts,
      actions: _actions,
      onNavigationNotification: _handlesBack,
      routerConfig: ref.watch(tvRouterProvider),
      builder: (context, child) {
        TvArtwork.sizeCache(MediaQuery.devicePixelRatioOf(context));
        return NotificationListener<ScrollNotification>(
          onNotification: images ? TvArtwork.onScroll : null,
          child: _Downloads(child: TvFocusWatchdog(child: child!)),
        );
      },
    );
  }
}

/// While the settings load: the bulbs. If that fails: why, and Try again.
class _Splash extends StatelessWidget {
  const _Splash({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    if (error == null) {
      return const ColoredBox(
        color: MarqueeColors.night,
        child: Center(child: BulbLoader()),
      );
    }
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    return Material(
      color: MarqueeColors.night,
      child: TvScreen(
        builder: (context, scroll) => Padding(
          padding: TvSpace.safe,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(errorMessage(l10n, error), style: text.body),
                const SizedBox(height: 24),
                TvZone.row(
                  order: 0,
                  initial: true,
                  keyline: 0,
                  child: TvButton(
                    index: 0,
                    primary: true,
                    label: l10n.retry,
                    onSelect: onRetry,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Starts the downloads engine once (it catches up with downloads that ran
/// while the app was closed) and keeps its notification texts in the UI
/// language, as the phone app does.
class _Downloads extends ConsumerStatefulWidget {
  const _Downloads({required this.child});

  final Widget child;

  @override
  ConsumerState<_Downloads> createState() => _DownloadsState();
}

class _DownloadsState extends ConsumerState<_Downloads>
    with WidgetsBindingObserver {
  Locale? _locale;
  StreamSubscription<String>? _tapsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tapsSub = ref.read(downloadsRepositoryProvider).notificationTaps.listen((
      _,
    ) {
      if (mounted) ref.read(tvRouterProvider).go('/downloads');
    });
  }

  @override
  void dispose() {
    _tapsSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(downloadsRepositoryProvider).reconcile());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _locale) return;
    final first = _locale == null;
    _locale = locale;
    final l10n = AppLocalizations.of(context);
    final notices = buildDownloadNotices(l10n);
    final downloads = ref.read(downloadsRepositoryProvider);
    unawaited(first ? downloads.start(notices) : downloads.setNotices(notices));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

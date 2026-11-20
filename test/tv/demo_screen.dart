import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/app/l10n/app_localizations.dart';
import 'package:cinemakom/tv/focus/tv_back.dart';
import 'package:cinemakom/tv/focus/tv_focus_watchdog.dart';
import 'package:cinemakom/tv/focus/tv_focusable.dart';
import 'package:cinemakom/tv/focus/tv_screen.dart';
import 'package:cinemakom/tv/focus/tv_zone.dart';
import 'package:cinemakom/tv/theme/tv_text.dart';
import 'package:cinemakom/tv/tv_keys.dart';
import 'package:cinemakom/tv/widgets/tv_button.dart';
import 'package:cinemakom/tv/widgets/tv_choice_panel.dart';
import 'package:cinemakom/tv/widgets/tv_focus_look.dart';
import 'package:cinemakom/tv/widgets/tv_text_entry.dart';

/// A screen with every kind of zone, for the focus rules (docs/TV.md TV-1):
///   0 actions ⟵⟶   Play · Favorite (pushes a page) · Trailer (disabled) ·
///                  Quality (opens a panel) · Hidden (inside ExcludeFocus)
///   1 split        seasons ↕ | episodes ▦ (play, download)
///   2 posters ⟵⟶   20 cards in a lazy horizontal list
///   3 rows ▦       title · Remove (removing one tests R7)
///   4 search       a text entry (R8)
class DemoApp extends StatelessWidget {
  const DemoApp({super.key, this.locale = const Locale('en'), this.log});

  final Locale locale;

  /// What the controls did, in order.
  final List<String>? log;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildMarqueeTvTheme(arabic: locale.languageCode == 'ar'),
    shortcuts: tvShortcuts,
    actions: {
      ...WidgetsApp.defaultActions,
      TvBackIntent: CallbackAction<TvBackIntent>(
        onInvoke: (_) => tvHandleBack(),
      ),
    },
    builder: (context, child) => TvFocusWatchdog(child: child!),
    home: DemoScreen(log: log ?? []),
  );
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, required this.log});

  final List<String> log;

  @override
  State<DemoScreen> createState() => DemoScreenState();
}

class DemoScreenState extends State<DemoScreen> {
  final rows = ['Row A', 'Row B', 'Row C', 'Row D'];
  final search = TextEditingController();
  int season = 0;
  String quality = '1080p';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _say(String what) => widget.log.add(what);

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return Scaffold(
      body: TvScreen(
        builder: (context, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: 27),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: TvZone.row(
                  order: 0,
                  initial: true,
                  child: Wrap(
                    spacing: 12,
                    children: [
                      TvButton(
                        index: 0,
                        label: 'Play',
                        primary: true,
                        onSelect: () => _say('play'),
                      ),
                      TvButton(
                        index: 1,
                        label: 'Favorite',
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _PushedPage(),
                          ),
                        ),
                      ),
                      const TvButton(
                        index: 2,
                        label: 'Trailer',
                        enabled: false,
                      ),
                      TvButton(
                        index: 3,
                        label: 'Quality $quality',
                        onSelect: () async {
                          final picked = await showTvChoicePanel<String>(
                            context,
                            title: 'Quality',
                            selected: quality,
                            choices: const [
                              TvChoice('2160p', '4K'),
                              TvChoice('1080p', '1080p'),
                              TvChoice('720p', '720p'),
                            ],
                          );
                          if (picked != null) setState(() => quality = picked);
                        },
                      ),
                      const ExcludeFocus(
                        child: Visibility(
                          visible: false,
                          maintainState: true,
                          child: TvButton(index: 4, label: 'Hidden'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 260,
                child: TvGroup.split(
                  order: 1,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TvZone.column(
                          order: 0,
                          initialIndex: season,
                          child: ListView(
                            padding: const EdgeInsetsDirectional.only(
                              start: 48,
                            ),
                            children: [
                              for (var s = 0; s < 6; s++)
                                _Cell(
                                  index: s,
                                  label: 'Season ${s + 1}',
                                  selected: s == season,
                                  onFocus: () => setState(() => season = s),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: TvZone.grid(
                          order: 1,
                          columns: 2,
                          child: ListView(
                            key: ValueKey(season),
                            children: [
                              for (var e = 0; e < 8; e++)
                                Row(
                                  children: [
                                    Expanded(
                                      child: _Cell(
                                        index: e * 2,
                                        label:
                                            'S${season + 1} Episode ${e + 1}',
                                      ),
                                    ),
                                    _Cell(
                                      index: e * 2 + 1,
                                      label: 'S${season + 1} Download ${e + 1}',
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 48),
                child: Text('Posters', style: text.sectionTitle),
              ),
              SizedBox(
                height: 200,
                child: TvZone.row(
                  order: 2,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    itemExtent: 130,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                    itemCount: 20,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.all(10),
                      child: TvFocusable(
                        index: i,
                        label: 'Poster $i',
                        onSelect: () => _say('open poster $i'),
                        onLongSelect: () => _say('menu poster $i'),
                        builder: (context, focused) => TvCardFocus(
                          focused: focused,
                          radius: 10,
                          child: const ColoredBox(color: Color(0xFF2C221A)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: TvZone.grid(
                  order: 3,
                  columns: 2,
                  child: Column(
                    children: [
                      for (final (i, row) in rows.indexed)
                        Row(
                          key: ValueKey(row),
                          children: [
                            Expanded(
                              child: _Cell(index: i * 2, label: row),
                            ),
                            TvButton(
                              index: i * 2 + 1,
                              label: 'Remove $row',
                              onSelect: () => setState(() => rows.remove(row)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: TvZone.row(
                  order: 4,
                  child: TvTextEntry(
                    index: 0,
                    controller: search,
                    label: 'Search',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.label,
    this.selected = false,
    this.onFocus,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
    index: index,
    label: label,
    onSelect: () {},
    builder: (context, focused) {
      if (focused && onFocus != null && !selected) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onFocus!());
      }
      return TvRing(
        on: focused,
        radius: 12,
        child: Container(
          height: 48,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label),
        ),
      );
    },
  );
}

class _PushedPage extends StatelessWidget {
  const _PushedPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TvScreen(
      builder: (context, scroll) => const Padding(
        padding: EdgeInsets.all(48),
        child: TvZone.row(
          order: 0,
          initial: true,
          child: Row(
            children: [
              TvButton(index: 0, label: 'Pushed A'),
              TvButton(index: 1, label: 'Pushed B'),
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/brand/cinemakom_mark.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../core/storage/preferences.dart';
import '../../../features/settings/settings_labels.dart';
import '../../focus/tv_focusable.dart';
import '../../focus/tv_panel.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../widgets/tv_choice_panel.dart';
import '../../widgets/tv_focus_look.dart';
import '../../widgets/tv_list_row.dart';
import '../../widgets/tv_shelf.dart';

/// Settings on TV (docs/TV.md §7.8, the TV Settings design): one column of
/// rows in groups (App: Language; Playback: Default quality, Default
/// subtitles, Subtitle size; About: Licenses), zone 0. OK opens a panel on
/// the current value. Changing the language turns the app RTL or LTR in
/// place, focus staying on the Language row. Screen rotation isn't here:
/// TVs don't rotate.
class TvSettingsScreen extends ConsumerWidget {
  const TvSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    Future<void> pick<T>(
      String title,
      List<TvChoice<T>> choices,
      T selected,
      Future<void> Function(T) save,
    ) async {
      final value = await showTvChoicePanel<T>(
        context,
        title: title,
        choices: choices,
        selected: selected,
      );
      if (value != null && value != selected) await save(value);
    }

    final language = settings.effectiveLanguage;
    var row = 0;
    Widget settingsRow(String label, String? value, VoidCallback onSelect) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TvSettingsRow(
            index: row++,
            label: label,
            value: value,
            onSelect: onSelect,
          ),
        );

    return TvScreen(
      order: 1,
      builder: (context, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsetsDirectional.fromSTEB(
          TvSpace.safeH,
          0,
          TvSpace.safeH,
          TvSpace.safeV,
        ),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: 620,
            child: TvZone.column(
              order: 0,
              keyline: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Heading(l10n.settingsGeneral),
                  settingsRow(
                    l10n.settingsLanguage,
                    language == AppLanguage.arabic
                        ? l10n.languageArabic
                        : l10n.languageEnglish,
                    () => pick(
                      l10n.settingsLanguage,
                      [
                        TvChoice(AppLanguage.english, l10n.languageEnglish),
                        TvChoice(AppLanguage.arabic, l10n.languageArabic),
                      ],
                      language,
                      notifier.setLanguage,
                    ),
                  ),
                  settingsRow(
                    l10n.settingsTheme,
                    themeLabel(l10n, settings.theme),
                    () => pick(
                      l10n.settingsTheme,
                      [
                        for (final t in AppThemeProfile.values)
                          TvChoice(t, themeLabel(l10n, t)),
                      ],
                      settings.theme,
                      notifier.setTheme,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Heading(l10n.settingsPlayback),
                  settingsRow(
                    l10n.settingsDefaultQuality,
                    qualityLabel(l10n, settings.defaultQuality),
                    () => pick(
                      l10n.settingsDefaultQuality,
                      [
                        for (final q in PreferredQuality.values)
                          TvChoice(q, qualityLabel(l10n, q)),
                      ],
                      settings.defaultQuality,
                      notifier.setDefaultQuality,
                    ),
                  ),
                  settingsRow(
                    l10n.settingsDefaultSubtitles,
                    subtitleLabel(l10n, settings.defaultSubtitle),
                    () => pick(
                      l10n.settingsDefaultSubtitles,
                      [
                        for (final s in SubtitlePreference.values)
                          TvChoice(s, subtitleLabel(l10n, s)),
                      ],
                      settings.defaultSubtitle,
                      notifier.setDefaultSubtitle,
                    ),
                  ),
                  settingsRow(
                    l10n.settingsSubtitleSize,
                    subtitleSizeLabel(l10n, settings.subtitleSize),
                    () => pick(
                      l10n.settingsSubtitleSize,
                      [
                        for (final s in SubtitleSize.values)
                          TvChoice(s, subtitleSizeLabel(l10n, s)),
                      ],
                      settings.subtitleSize,
                      notifier.setSubtitleSize,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Heading(l10n.settingsHelp),
                  settingsRow(
                    l10n.settingsAbout,
                    null,
                    () => context.push('/settings/licenses'),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const CinemakomMark(size: 32, semanticLabel: null),
                      const SizedBox(width: 12),
                      Text(
                        l10n.appTitle,
                        style: MarqueeTvText.of(context).caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A group's heading: 13, 600, tracked, `dust` (the design).
class _Heading extends StatelessWidget {
  const _Heading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.arabic ? title : title.toUpperCase(),
        style: text.caption
            .copyWith(fontSize: 13, letterSpacing: text.arabic ? 0 : 13 * 0.14)
            .withWeight(FontWeight.w600),
      ),
    );
  }
}

/// Every package's licenses, newest Flutter registry order.
final _licensesProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  final byPackage = <String, List<String>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs.map((p) => p.text).join('\n\n');
    for (final package in entry.packages) {
      (byPackage[package] ??= []).add(text);
    }
  }
  final names = byPackage.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return {for (final n in names) n: byPackage[n]!.join('\n\n────────\n\n')};
});

/// The licenses (Settings → About and licenses): the app's name, then one
/// row per package (zone 0); OK shows its licence in a panel, read with Up
/// and Down.
class TvLicensesScreen extends ConsumerWidget {
  const TvLicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final licenses = ref.watch(_licensesProvider).value;
    final title = l10n.settingsAbout;
    return TvScreen(
      // The page's place in the tab shell, under the tabs.
      order: 1,
      builder: (context, scroll) => Padding(
        padding: TvSpace.safe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text.arabic ? title : title.toUpperCase(),
              style: text.displayLarge.copyWith(fontSize: 36),
            ),
            const SizedBox(height: 6),
            Text(l10n.appTitle, style: text.caption),
            const SizedBox(height: 18),
            Expanded(
              child: licenses == null
                  ? Center(child: BulbLoader(semanticLabel: l10n.loading))
                  : Align(
                      alignment: AlignmentDirectional.topStart,
                      child: SizedBox(
                        width: 620,
                        child: TvZone.column(
                          order: 0,
                          initial: true,
                          keyline: 0,
                          child: ListView.separated(
                            controller: scroll,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: licenses.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final name = licenses.keys.elementAt(i);
                              return TvListRow(
                                index: i,
                                label: name,
                                onSelect: () => _showLicence(
                                  context,
                                  name,
                                  licenses[name]!,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showLicence(BuildContext context, String name, String body) =>
    showTvSidePanel<void>(
      context,
      width: 620,
      builder: (context, scroll) {
        final text = MarqueeTvText.of(context);
        final l10n = AppLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: text.panelTitle.copyWith(fontSize: 26)),
            const SizedBox(height: 16),
            Expanded(
              child: TvZone.column(
                order: 0,
                initial: true,
                keyline: 0,
                child: _ScrollingText(body: body, scroll: scroll, label: name),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.tvBackCloses, style: text.caption),
          ],
        );
      },
    );

/// Long text read with the remote: one focusable item; Up and Down scroll
/// it, a page at a time when held.
class _ScrollingText extends StatelessWidget {
  const _ScrollingText({
    required this.body,
    required this.scroll,
    required this.label,
  });

  final String body;
  final ScrollController scroll;
  final String label;

  static const _step = 96.0;

  KeyEventResult _key(KeyEvent event) {
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    if (!down && key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyUpEvent && scroll.hasClients) {
      final p = scroll.position;
      final to = (p.pixels + (down ? _step : -_step)).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      scroll.jumpTo(to);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => TvFocusable(
    index: 0,
    label: label,
    onKey: _key,
    builder: (context, focused) => TvRing(
      on: focused,
      radius: 12,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.night,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          controller: scroll,
          child: Text(
            body,
            style: MarqueeTvText.of(context).caption
                .copyWith(color: context.palette.creamSoft, height: 1.5),
          ),
        ),
      ),
    ),
  );
}

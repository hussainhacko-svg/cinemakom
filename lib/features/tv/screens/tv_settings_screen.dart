import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/brand/cinemakom_mark.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart' show AppRoutes;
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/choice_picker.dart';
import '../../../core/storage/preferences.dart';
import '../../settings/settings_screen.dart'
    show qualityLabel, subtitleLabel, subtitleSizeLabel;
import '../../settings/widgets/settings_group.dart';
import '../tv_shell.dart' show tvGutter;
import '../widgets/tv_focus.dart';

/// Dedicated 10-foot Android TV Settings: language, default quality,
/// subtitles, subtitle size, about. No screen rotation (TVs are landscape)
/// and no desktop download folder.
class TvSettingsScreen extends ConsumerWidget {
  const TvSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    Future<void> pick<T>(
      String title,
      List<Choice<T>> choices,
      T selected,
      Future<void> Function(T) save,
    ) async {
      final value = await showChoicePicker(
        context,
        title: title,
        choices: choices,
        selected: selected,
      );
      if (value != null && value != selected) await save(value);
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvPageHeader(title: l10n.navSettings),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640 + 2 * tvGutter),
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    tvGutter,
                    MarqueeSpace.s,
                    tvGutter,
                    MarqueeSpace.huge,
                  ),
                  children: [
                    SettingsGroup(
                      title: l10n.settingsGeneral,
                      rows: [
                        SettingsRow(
                          label: l10n.settingsLanguage,
                          value:
                              settings.effectiveLanguage == AppLanguage.arabic
                              ? l10n.languageArabic
                              : l10n.languageEnglish,
                          onTap: () => pick(
                            l10n.settingsLanguage,
                            [
                              Choice(
                                AppLanguage.english,
                                l10n.languageEnglish,
                                labelStyle: const MarqueeText(
                                  arabic: false,
                                ).title,
                              ),
                              Choice(
                                AppLanguage.arabic,
                                l10n.languageArabic,
                                labelStyle: const MarqueeText(
                                  arabic: true,
                                ).title,
                              ),
                            ],
                            settings.effectiveLanguage,
                            notifier.setLanguage,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MarqueeSpace.xxl),
                    SettingsGroup(
                      title: l10n.settingsPlayback,
                      rows: [
                        SettingsRow(
                          label: l10n.settingsDefaultQuality,
                          value: qualityLabel(l10n, settings.defaultQuality),
                          onTap: () => pick(
                            l10n.settingsDefaultQuality,
                            [
                              for (final q in PreferredQuality.values)
                                Choice(q, qualityLabel(l10n, q)),
                            ],
                            settings.defaultQuality,
                            notifier.setDefaultQuality,
                          ),
                        ),
                        SettingsRow(
                          label: l10n.settingsDefaultSubtitles,
                          value: subtitleLabel(l10n, settings.defaultSubtitle),
                          onTap: () => pick(
                            l10n.settingsDefaultSubtitles,
                            [
                              for (final s in SubtitlePreference.values)
                                Choice(s, subtitleLabel(l10n, s)),
                            ],
                            settings.defaultSubtitle,
                            notifier.setDefaultSubtitle,
                          ),
                        ),
                        SettingsRow(
                          label: l10n.settingsSubtitleSize,
                          value: subtitleSizeLabel(l10n, settings.subtitleSize),
                          onTap: () => pick(
                            l10n.settingsSubtitleSize,
                            [
                              for (final s in SubtitleSize.values)
                                Choice(s, subtitleSizeLabel(l10n, s)),
                            ],
                            settings.subtitleSize,
                            notifier.setSubtitleSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MarqueeSpace.xxl),
                    SettingsGroup(
                      title: l10n.settingsHelp,
                      rows: [
                        SettingsRow(
                          label: l10n.settingsAbout,
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: l10n.appTitle,
                            applicationIcon: const Padding(
                              padding: EdgeInsets.all(MarqueeSpace.l),
                              child: CinemakomMark(size: 64),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: MarqueeSpace.xxl),
                      // Developer tools: debug builds only, so not localized.
                      SettingsGroup(
                        title: 'Developer',
                        rows: [
                          SettingsRow(
                            label: 'API check',
                            onTap: () => context.go(AppRoutes.debug),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: MarqueeSpace.huge),
                    Column(
                      children: [
                        const CinemakomMark(size: 40, semanticLabel: null),
                        const SizedBox(height: MarqueeSpace.s),
                        Text(l10n.appTitle, style: text.caption),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

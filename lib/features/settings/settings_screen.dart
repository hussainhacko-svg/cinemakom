import 'package:file_selector/file_selector.dart' show getDirectoryPath;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/router.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/choice_picker.dart';
import '../../app/widgets/tab_page.dart';
import '../../core/platform/platform_info.dart';
import '../../core/storage/preferences.dart';
import '../../data/repositories/downloads_repository.dart' show defaultDesktopFolder;
import 'widgets/settings_group.dart';

/// Settings: language, screen rotation (phones and tablets), default
/// quality, subtitles and subtitle size, help (DESIGN.md §8).
/// Changes apply at once and are saved.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);

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

    final languages = [
      Choice(
        AppLanguage.english,
        l10n.languageEnglish,
        labelStyle: const MarqueeText(arabic: false).title,
      ),
      Choice(
        AppLanguage.arabic,
        l10n.languageArabic,
        labelStyle: const MarqueeText(arabic: true).title,
      ),
    ];
    final qualities = [
      for (final q in PreferredQuality.values) Choice(q, qualityLabel(l10n, q)),
    ];
    final subtitles = [
      for (final s in SubtitlePreference.values)
        Choice(s, subtitleLabel(l10n, s)),
    ];
    final rotations = [
      for (final r in ScreenRotation.values) Choice(r, rotationLabel(l10n, r)),
    ];
    final sizes = [
      for (final s in SubtitleSize.values)
        Choice(s, subtitleSizeLabel(l10n, s)),
    ];

    return TabPage(
      title: l10n.navSettings,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640 + 2 * 48),
          child: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
              gutter,
              MarqueeSpace.s,
              gutter,
              MarqueeSpace.huge,
            ),
            children: [
              SettingsGroup(
                title: l10n.settingsGeneral,
                rows: [
                  SettingsRow(
                    label: l10n.settingsLanguage,
                    value: settings.effectiveLanguage == AppLanguage.arabic
                        ? l10n.languageArabic
                        : l10n.languageEnglish,
                    onTap: () => pick(
                      l10n.settingsLanguage,
                      languages,
                      settings.effectiveLanguage,
                      notifier.setLanguage,
                    ),
                  ),
                  if (isMobile)
                    SettingsRow(
                      label: l10n.settingsScreenRotation,
                      value: rotationLabel(l10n, settings.screenRotation),
                      onTap: () => pick(
                        l10n.settingsScreenRotation,
                        rotations,
                        settings.screenRotation,
                        notifier.setScreenRotation,
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
                      qualities,
                      settings.defaultQuality,
                      notifier.setDefaultQuality,
                    ),
                  ),
                  SettingsRow(
                    label: l10n.settingsDefaultSubtitles,
                    value: subtitleLabel(l10n, settings.defaultSubtitle),
                    onTap: () => pick(
                      l10n.settingsDefaultSubtitles,
                      subtitles,
                      settings.defaultSubtitle,
                      notifier.setDefaultSubtitle,
                    ),
                  ),
                  SettingsRow(
                    label: l10n.settingsSubtitleSize,
                    value: subtitleSizeLabel(l10n, settings.subtitleSize),
                    onTap: () => pick(
                      l10n.settingsSubtitleSize,
                      sizes,
                      settings.subtitleSize,
                      notifier.setSubtitleSize,
                    ),
                  ),
                ],
              ),
              if (isDesktop) ...[
                const SizedBox(height: MarqueeSpace.xxl),
                SettingsGroup(
                  title: l10n.settingsDownloads,
                  rows: [
                    SettingsRow(
                      label: l10n.settingsDownloadFolder,
                      value: settings.downloadFolder ?? defaultDesktopFolder(),
                      onTap: () async {
                        final folder = await getDirectoryPath(
                          initialDirectory:
                              settings.downloadFolder ?? defaultDesktopFolder(),
                          confirmButtonText: l10n.settingsDownloadFolder,
                        );
                        if (folder != null) {
                          await notifier.setDownloadFolder(folder);
                        }
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: MarqueeSpace.s,
                    start: MarqueeSpace.xs,
                  ),
                  child: Text(
                    l10n.settingsDownloadFolderNote,
                    style: text.caption,
                  ),
                ),
              ],
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
    );
  }
}

String qualityLabel(AppLocalizations l10n, PreferredQuality q) =>
    q == PreferredQuality.p2160
    ? l10n.quality4k(q.height)
    : l10n.qualityHeight(q.height);

String subtitleLabel(AppLocalizations l10n, SubtitlePreference s) =>
    switch (s) {
      SubtitlePreference.arabic => l10n.subtitleArabic,
      SubtitlePreference.english => l10n.subtitleEnglish,
      SubtitlePreference.off => l10n.subtitleOff,
    };

String subtitleSizeLabel(AppLocalizations l10n, SubtitleSize s) => switch (s) {
  SubtitleSize.small => l10n.subtitleSizeSmall,
  SubtitleSize.medium => l10n.subtitleSizeMedium,
  SubtitleSize.large => l10n.subtitleSizeLarge,
};

String rotationLabel(AppLocalizations l10n, ScreenRotation r) => switch (r) {
  ScreenRotation.portrait => l10n.rotationPortrait,
  ScreenRotation.auto => l10n.rotationAuto,
};

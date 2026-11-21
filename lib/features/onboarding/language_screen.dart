import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/theme/marquee_theme.dart';
import '../../core/storage/preferences.dart';

/// First launch: pick English or Arabic before anything else (DESIGN.md §8).
/// The screen previews the pick at once (Arabic flips it to RTL); Continue
/// saves it, and the router then moves on to Home.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  // Start from the device language, so most people only tap Continue.
  AppLanguage _choice =
      PlatformDispatcher.instance.locale.languageCode == AppLanguage.arabic.code
      ? AppLanguage.arabic
      : AppLanguage.english;

  @override
  Widget build(BuildContext context) {
    final arabic = _choice == AppLanguage.arabic;
    return Localizations.override(
      context: context,
      locale: _choice.locale,
      child: Theme(
        data: buildMarqueeTheme(arabic: arabic),
        child: Builder(builder: _buildPage),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final english = lookupAppLocalizations(AppLanguage.english.locale);
    final arabic = lookupAppLocalizations(AppLanguage.arabic.locale);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    // Scales down rather than overflowing on narrow
                    // windows or with large text.
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: CinemakomLogo(markSize: 72),
                      ),
                    ),
                  ),
                  // Shown in both languages, whatever is picked.
                  Semantics(
                    header: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          english.chooseLanguage,
                          style: const MarqueeText(arabic: false).title
                              .copyWith(fontSize: 18),
                        ),
                        Text(
                          arabic.chooseLanguage,
                          style: const MarqueeText(arabic: true).body,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MarqueeSpace.l),
                  _LanguageOption(
                    label: english.languageEnglish,
                    style: const MarqueeText(arabic: false).displayLarge
                        .copyWith(fontSize: 26),
                    selected: _choice == AppLanguage.english,
                    onTap: () => setState(() => _choice = AppLanguage.english),
                  ),
                  const SizedBox(height: MarqueeSpace.m),
                  _LanguageOption(
                    label: arabic.languageArabic,
                    style: const MarqueeText(arabic: true).displayLarge
                        .copyWith(fontSize: 24)
                        .withWeight(FontWeight.w700),
                    selected: _choice == AppLanguage.arabic,
                    onTap: () => setState(() => _choice = AppLanguage.arabic),
                  ),
                  const SizedBox(height: MarqueeSpace.xxl),
                  FilledButton(
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .setLanguage(_choice),
                    child: Text(l10n.continueAction),
                  ),
                  const SizedBox(height: MarqueeSpace.m),
                  Text(
                    l10n.changeLanguageLater,
                    textAlign: TextAlign.center,
                    style: text.caption,
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

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? context.palette.bulb : context.palette.velvetStrong;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      label: label,
      child: Material(
        color: context.palette.booth,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(MarqueeRadius.panel),
          side: BorderSide(
            color: selected ? context.palette.bulb : context.palette.velvet,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 68,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: style)),
                  // A radio mark: ring, filled when selected.
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.palette.bulb,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(dimension: 10),
                          )
                        : null,
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

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/brand/cinemakom_mark.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/theme/marquee_theme.dart';
import '../../../core/storage/preferences.dart';

/// First-launch language picker for Android TV: horizontal 16:9 layout with
/// side-by-side English | العربية cards and a prominent Continue button.
class TvLanguageScreen extends ConsumerStatefulWidget {
  const TvLanguageScreen({super.key});

  @override
  ConsumerState<TvLanguageScreen> createState() => _TvLanguageScreenState();
}

class _TvLanguageScreenState extends ConsumerState<TvLanguageScreen> {
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
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: CinemakomLogo(markSize: 64)),
                const SizedBox(height: MarqueeSpace.xxl),
                Semantics(
                  header: true,
                  child: Column(
                    children: [
                      Text(
                        english.chooseLanguage,
                        textAlign: TextAlign.center,
                        style: const MarqueeText(arabic: false).title
                            .copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        arabic.chooseLanguage,
                        textAlign: TextAlign.center,
                        style: const MarqueeText(arabic: true).body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MarqueeSpace.xl),
                Row(
                  children: [
                    Expanded(
                      child: _TvLanguageCard(
                        label: english.languageEnglish,
                        style: const MarqueeText(arabic: false).displayLarge
                            .copyWith(fontSize: 28),
                        selected: _choice == AppLanguage.english,
                        onTap: () =>
                            setState(() => _choice = AppLanguage.english),
                      ),
                    ),
                    const SizedBox(width: MarqueeSpace.l),
                    Expanded(
                      child: _TvLanguageCard(
                        label: arabic.languageArabic,
                        style: const MarqueeText(arabic: true).displayLarge
                            .copyWith(fontSize: 26)
                            .withWeight(FontWeight.w700),
                        selected: _choice == AppLanguage.arabic,
                        onTap: () =>
                            setState(() => _choice = AppLanguage.arabic),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MarqueeSpace.xxl),
                Center(
                  child: FilledButton(
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .setLanguage(_choice),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(240, 52),
                    ),
                    child: Text(l10n.continueAction),
                  ),
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
    );
  }
}

class _TvLanguageCard extends StatefulWidget {
  const _TvLanguageCard({
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
  State<_TvLanguageCard> createState() => _TvLanguageCardState();
}

class _TvLanguageCardState extends State<_TvLanguageCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final accent = selected ? MarqueeColors.bulb : MarqueeColors.velvetStrong;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      label: widget.label,
      child: Material(
        color: _focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(MarqueeRadius.panel),
          side: BorderSide(
            color: _focused
                ? MarqueeColors.bulbBright
                : selected
                ? MarqueeColors.bulb
                : MarqueeColors.velvet,
            width: _focused ? 3 : 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: selected,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          focusColor: Colors.transparent,
          child: SizedBox(
            height: 80,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: Text(widget.label, style: widget.style)),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? const DecoratedBox(
                            decoration: BoxDecoration(
                              color: MarqueeColors.bulb,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(dimension: 11),
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

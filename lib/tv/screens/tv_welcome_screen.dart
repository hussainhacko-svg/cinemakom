import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../core/storage/preferences.dart';
import '../focus/tv_focusable.dart';
import '../focus/tv_screen.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import '../widgets/tv_focus_look.dart';

/// First launch on TV (docs/TV.md §7.8, the TV language design): the
/// lockup, "Choose your language" in both languages, and two large buttons,
/// English focused. OK picks one and opens Home.
class TvWelcomeScreen extends ConsumerWidget {
  const TvWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final english = lookupAppLocalizations(const Locale('en'));
    final arabic = lookupAppLocalizations(const Locale('ar'));
    final text = MarqueeTvText.of(context);
    void choose(AppLanguage language) =>
        ref.read(settingsProvider.notifier).setLanguage(language);
    return Scaffold(
      body: TvScreen(
        builder: (context, scroll) => Padding(
          padding: TvSpace.safe,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CinemakomLogo(markSize: 64),
                const SizedBox(height: 34),
                Text(
                  english.chooseLanguage,
                  style: text.title.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  arabic.chooseLanguage,
                  textDirection: TextDirection.rtl,
                  style: text.title.copyWith(
                    fontSize: 22,
                    fontFamily: MarqueeFonts.uiArabic,
                    color: context.palette.creamSoft,
                  ),
                ),
                const SizedBox(height: 34),
                TvZone.row(
                  order: 0,
                  initial: true,
                  keyline: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LanguageButton(
                        index: 0,
                        label: english.languageEnglish,
                        onSelect: () => choose(AppLanguage.english),
                      ),
                      const SizedBox(width: 24),
                      _LanguageButton(
                        index: 1,
                        label: arabic.languageArabic,
                        arabicText: true,
                        onSelect: () => choose(AppLanguage.arabic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  '${english.changeLanguageLater} · ${arabic.changeLanguageLater}',
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

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.index,
    required this.label,
    required this.onSelect,
    this.arabicText = false,
  });

  final int index;
  final String label;
  final VoidCallback onSelect;
  final bool arabicText;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: label,
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 16,
        gap: TvFocusStyle.buttonGap,
        child: Container(
          width: 240,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? context.palette.boothRaised : context.palette.booth,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: focused
                  ? context.palette.velvetStrong
                  : context.palette.velvet,
            ),
          ),
          child: Text(
            label,
            textDirection: arabicText ? TextDirection.rtl : TextDirection.ltr,
            style: text.title
                .copyWith(
                  fontSize: 22,
                  fontFamily: arabicText ? MarqueeFonts.uiArabic : null,
                )
                .withWeight(FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

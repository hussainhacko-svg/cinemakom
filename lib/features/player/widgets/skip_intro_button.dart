import 'package:material_ui/material_ui.dart';

import 'controls_overlay.dart' show withFocusRing;
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';

/// "Skip intro": an outlined pill at the end side above the seek bar
/// (PLAYER.md §7.5). [visible] is false once it has folded into the
/// controls and they are hidden.
class SkipIntroButton extends StatelessWidget {
  const SkipIntroButton({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.bottomEnd,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            end: width >= 600 ? MarqueeSpace.xxxl : MarqueeSpace.l,
            bottom: 72,
          ),
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.skip_next, size: 20),
                iconAlignment: IconAlignment.end,
                label: Text(AppLocalizations.of(context).playerSkipIntro),
                style: withFocusRing(
                  context,
                  OutlinedButton.styleFrom(
                    backgroundColor: context.palette.booth,
                    foregroundColor: context.palette.cream,
                    side: BorderSide(color: context.palette.cream),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: MarqueeSpace.l,
                    ),
                    textStyle: MarqueeText.of(context).label
                        .copyWith(fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import 'brand/cinemakom_mark.dart';
import 'l10n/app_localizations.dart';
import 'theme/marquee_colors.dart';
import 'theme/marquee_text.dart';
import 'widgets/bulb_loader.dart';

/// The in-app splash: the mark on Night (matching the native splash) with
/// the bulb loader under it, shown while [appStartupProvider] loads. When
/// startup fails it shows the error and a retry button instead.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.onRetry});

  /// Set when startup failed.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final retry = onRetry;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CinemakomMark(size: 96),
            const SizedBox(height: MarqueeSpace.huge),
            if (retry == null)
              BulbLoader(semanticLabel: l10n.appTitle)
            else ...[
              Text(
                l10n.startupFailed,
                style: text.title.copyWith(color: context.palette.cream),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: MarqueeSpace.l),
              FilledButton(onPressed: retry, child: Text(l10n.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

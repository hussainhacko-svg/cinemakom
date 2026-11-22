import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/media_text.dart';
import '../focus/tv_panel.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_text.dart';
import 'tv_button.dart';

/// One code in a [showTvQrPanel]: what scanning it does ([label], "By
/// email"), the [data] it holds, and a short form to type instead
/// ([short], "me@sharon-xa.com").
typedef TvQrCode = ({String label, String data, String short});

/// A side panel of QR codes to scan with a phone: TVs rarely have a mail app
/// or a browser, so links open on the phone instead. The [title], "Scan with
/// your phone's camera", the codes side by side, then OK (focused) and "Back
/// closes".
Future<void> showTvQrPanel(
  BuildContext context, {
  required String title,
  required List<TvQrCode> codes,
}) => showTvSidePanel<void>(
  context,
  width: 480,
  builder: (context, scroll) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text.arabic ? title : title.toUpperCase(), style: text.panelTitle),
        const SizedBox(height: 8),
        Text(l10n.tvScanWithPhone, style: text.caption),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, code) in codes.indexed) ...[
              if (i > 0) const SizedBox(width: 32),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dark on light, with a quiet edge: what phone cameras
                    // read best.
                    QrImageView(
                      data: code.data,
                      size: 150,
                      padding: const EdgeInsets.all(10),
                      backgroundColor: MarqueeColors.cream,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: MarqueeColors.night,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: MarqueeColors.night,
                      ),
                      semanticsLabel: code.label,
                    ),
                    const SizedBox(height: 12),
                    Text(code.label, style: text.label),
                    const SizedBox(height: 4),
                    Text(
                      context.isolate(code.short),
                      style: text.caption,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const Spacer(),
        TvZone.column(
          order: 0,
          initial: true,
          keyline: 0,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TvButton(
              index: 0,
              label: l10n.tvOk,
              onSelect: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.tvBackCloses, style: text.caption),
      ],
    );
  },
);

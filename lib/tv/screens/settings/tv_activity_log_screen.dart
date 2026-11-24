import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../core/diagnostics/event_log.dart';
import '../../../features/settings/activity_log_flow.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_qr_panel.dart';

/// Settings → Help → Activity log on TV: a TV has no share sheet, so "Open
/// it on your phone" serves the log on the Wi-Fi while a QR code for it is
/// shown (activity_log_flow.dart). The newest entries are below; they
/// aren't focusable (hundreds of lines aren't for a remote), the full log
/// reads better on the phone.
class TvActivityLogScreen extends ConsumerStatefulWidget {
  const TvActivityLogScreen({super.key});

  /// Entries built at most (those that fit show).
  static const shown = 40;

  @override
  ConsumerState<TvActivityLogScreen> createState() =>
      _TvActivityLogScreenState();
}

class _TvActivityLogScreenState extends ConsumerState<TvActivityLogScreen> {
  /// A message under the buttons (no Wi-Fi, cleared, failed).
  String? _note;

  Future<void> _toPhone() async {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(activityLogActionsProvider);
    try {
      final file = await actions.export();
      final server = await actions.serve(file);
      if (!mounted) {
        await server?.close();
        return;
      }
      if (server == null) {
        setState(() => _note = l10n.activityLogNoNetwork);
        return;
      }
      setState(() => _note = null);
      logEvent('log', 'served on the local network');
      try {
        await showTvQrPanel(
          context,
          title: l10n.activityLogToPhone,
          note: l10n.activityLogSameWifi,
          codes: [
            (
              label: l10n.settingsActivityLog,
              data: '${server.url}',
              short: '${server.url.host}:${server.url.port}',
            ),
          ],
        );
      } finally {
        await server.close();
      }
    } on Object catch (e) {
      logEvent('log', 'serving failed: $e');
      if (mounted) setState(() => _note = l10n.activityLogFailed);
    }
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    await ref.read(activityLogActionsProvider).clear();
    if (mounted) setState(() => _note = l10n.activityLogCleared);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final entries = ref.watch(activityLogProvider).value ?? const [];
    final folder = ref.read(activityLogActionsProvider).folder;
    final title = l10n.settingsActivityLog;
    final note = _note;
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
            SizedBox(
              width: 620,
              child: Text(l10n.activityLogNote, style: text.caption),
            ),
            const SizedBox(height: 18),
            TvZone.row(
              order: 0,
              initial: true,
              keyline: 0,
              child: Row(
                children: [
                  TvButton(
                    index: 0,
                    primary: true,
                    label: l10n.activityLogToPhone,
                    onSelect: () => unawaited(_toPhone()),
                  ),
                  const SizedBox(width: 12),
                  TvButton(
                    index: 1,
                    label: l10n.activityLogClear,
                    onSelect: () => unawaited(_clear()),
                  ),
                ],
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(note, style: text.body),
            ],
            if (folder != null) ...[
              const SizedBox(height: 10),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  l10n.activityLogAdb(folder),
                  style: text.caption.copyWith(color: MarqueeColors.dustDim),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: entries.isEmpty
                  ? Text(l10n.activityLogEmpty, style: text.caption)
                  : Directionality(
                      textDirection: TextDirection.ltr,
                      // As many as fit; not focusable or scrollable (the
                      // full log reads better on the phone).
                      child: ListView.builder(
                        primary: false,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: entries.length.clamp(
                          0,
                          TvActivityLogScreen.shown,
                        ),
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          return Text(
                            _line(e),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.caption.copyWith(
                              color: e.tag == 'error' || e.tag == 'freeze'
                                  ? MarqueeColors.ember
                                  : MarqueeColors.creamSoft,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _line(LogEntry e) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = e.at;
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  ${e.tag}  '
        '${e.message.split('\n').first}';
  }
}

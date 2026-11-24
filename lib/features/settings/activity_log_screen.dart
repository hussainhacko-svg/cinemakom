import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/sub_page.dart';
import '../../core/diagnostics/event_log.dart';
import '../../core/platform/platform_info.dart';
import 'activity_log_flow.dart';

/// Settings → Help → Activity log (phones and computers): what the app did
/// recently, and a way to hand it over. The TV has its own
/// (`TvActivityLogScreen`).
class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final entries = ref.watch(activityLogProvider).value ?? const [];
    final actions = ref.read(activityLogActionsProvider);
    final folder = actions.folder;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SubPageHeader(title: l10n.settingsActivityLog, gutter: gutter),
            SliverPadding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              sliver: SliverList.list(
                children: [
                  Text(
                    l10n.activityLogNote,
                    style: text.body.copyWith(color: MarqueeColors.creamSoft),
                  ),
                  const SizedBox(height: MarqueeSpace.l),
                  Wrap(
                    spacing: MarqueeSpace.m,
                    runSpacing: MarqueeSpace.s,
                    children: [
                      if (isDesktop)
                        FilledButton.icon(
                          onPressed: () => _save(context, ref),
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: Text(l10n.activityLogSave),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () => _share(context, ref),
                          icon: const Icon(Icons.share, size: 18),
                          label: Text(l10n.activityLogShare),
                        ),
                      OutlinedButton(
                        onPressed: () => _clear(context, ref),
                        child: Text(l10n.activityLogClear),
                      ),
                    ],
                  ),
                  if (isAndroid && folder != null) ...[
                    const SizedBox(height: MarqueeSpace.m),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        l10n.activityLogAdb(folder),
                        style: text.caption,
                      ),
                    ),
                  ],
                  const SizedBox(height: MarqueeSpace.xl),
                  if (entries.isEmpty)
                    Text(l10n.activityLogEmpty, style: text.caption),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(
                gutter,
                0,
                gutter,
                MarqueeSpace.huge,
              ),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (_, i) => LogEntryLine(entries[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(activityLogActionsProvider);
    try {
      final file = await actions.export();
      await actions.share(file, subject: l10n.settingsActivityLog);
    } on Object catch (e) {
      logEvent('log', 'share failed: $e');
      if (context.mounted) _say(context, l10n.activityLogFailed);
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(activityLogActionsProvider);
    try {
      final file = await actions.export();
      final to = await actions.saveCopy(file, confirm: l10n.activityLogSave);
      if (to != null && context.mounted) {
        _say(context, l10n.activityLogSaved(to));
      }
    } on Object catch (e) {
      logEvent('log', 'save failed: $e');
      if (context.mounted) _say(context, l10n.activityLogFailed);
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(activityLogActionsProvider).clear();
    if (context.mounted) _say(context, l10n.activityLogCleared);
  }

  static void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
}

/// One entry: its time, its tag and what happened. Technical English, so
/// always left to right, in Arabic too.
class LogEntryLine extends StatelessWidget {
  const LogEntryLine(this.entry, {super.key, this.maxLines = 6});

  final LogEntry entry;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final caption = MarqueeText.of(context).caption;
    final t = entry.at;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final problem = entry.tag == 'error' || entry.tag == 'freeze';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MarqueeSpace.xs),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$time  ',
                style: const TextStyle(color: MarqueeColors.dustDim),
              ),
              TextSpan(
                text: '${entry.tag}  ',
                style: TextStyle(
                  color: problem ? MarqueeColors.ember : MarqueeColors.bulb,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: entry.message,
                style: const TextStyle(color: MarqueeColors.cream),
              ),
            ],
          ),
          style: caption,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

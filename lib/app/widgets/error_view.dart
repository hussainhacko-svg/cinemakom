import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/service_status.dart';
import '../../data/repositories/status_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';

/// Cinemana's health, asked once when an API call has failed (the public
/// status page is the only third-party call allowed, AGENTS.md). Kept while
/// any error view shows it, so several failing rows ask only once.
final cinemanaHealthProvider = FutureProvider.autoDispose<ServiceHealth>(
  (ref) => ref.read(statusRepositoryProvider).cinemanaHealth(),
);

/// The user-facing message for [error]. When the status page says Cinemana
/// is down, that is said instead of blaming the connection.
String errorMessage(
  AppLocalizations l10n,
  Object error, {
  ServiceHealth? health,
}) {
  if (health?.isDown ?? false) return l10n.errorCinemanaDown;
  if (error is ApiException) {
    return switch (error.kind) {
      ApiErrorKind.network => l10n.errorNetwork,
      ApiErrorKind.timeout => l10n.errorTimeout,
      _ => l10n.errorServer,
    };
  }
  return l10n.errorServer;
}

/// An error message with a "Try again" button. [compact] is for one row or
/// the end of a list; otherwise it centres itself in the space it has.
class ErrorView extends ConsumerWidget {
  const ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final health = error is ApiException
        ? ref.watch(cinemanaHealthProvider).value
        : null;
    final message = Text(
      errorMessage(l10n, error, health: health),
      textAlign: compact ? TextAlign.start : TextAlign.center,
      style: text.body.copyWith(color: MarqueeColors.creamSoft),
    );
    final button = OutlinedButton(
      onPressed: () {
        ref.invalidate(cinemanaHealthProvider);
        onRetry();
      },
      child: Text(l10n.retry),
    );
    if (compact) {
      return Row(
        children: [
          Expanded(child: message),
          const SizedBox(width: MarqueeSpace.m),
          button,
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MarqueeSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message,
            const SizedBox(height: MarqueeSpace.l),
            button,
          ],
        ),
      ),
    );
  }
}

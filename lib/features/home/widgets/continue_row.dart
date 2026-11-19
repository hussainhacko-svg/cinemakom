import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/widgets/section_header.dart';
import '../../library/library_providers.dart';
import '../../library/widgets/continue_card.dart';

/// Home's Continue watching row (DESIGN.md §5 continue cards): the same
/// list as the Library's ([continueEntriesProvider]). A tap plays where it
/// was left, or the next episode. Hidden when empty.
class ContinueRow extends ConsumerWidget {
  const ContinueRow({super.key});

  static const _cardWidth = 300.0;
  static const _cardHeight = 100.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueEntriesProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: gutter,
              end: gutter - MarqueeSpace.s,
              bottom: MarqueeSpace.s,
            ),
            child: SectionHeader(
              title: AppLocalizations.of(context).rowContinueWatching,
            ),
          ),
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: MarqueeSpace.m),
              itemBuilder: (_, i) => SizedBox(
                width: _cardWidth,
                child: ContinueCard(entry: items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

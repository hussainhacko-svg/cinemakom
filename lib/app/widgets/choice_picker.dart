import 'package:material_ui/material_ui.dart';

import '../shell/app_shell.dart';
import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';

/// One option in [showChoicePicker].
class Choice<T> {
  const Choice(this.value, this.label, {this.labelStyle});

  final T value;
  final String label;

  /// Overrides the row's text style (e.g. a language name in its own font).
  final TextStyle? labelStyle;
}

/// Lets the user pick one of [choices]. A bottom sheet on narrow windows, a
/// dialog on wide ones (DESIGN.md §8). Returns null when dismissed.
Future<T?> showChoicePicker<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  required T selected,
}) {
  final content = _ChoiceList(
    title: title,
    choices: choices,
    selected: selected,
  );
  if (MediaQuery.sizeOf(context).width < Breakpoints.rail) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => content,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.xl),
          child: content,
        ),
      ),
    ),
  );
}

class _ChoiceList<T> extends StatelessWidget {
  const _ChoiceList({
    required this.title,
    required this.choices,
    required this.selected,
  });

  final String title;
  final List<Choice<T>> choices;
  final T selected;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(bottom: MarqueeSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              MarqueeSpace.xxl,
              0,
              MarqueeSpace.xxl,
              MarqueeSpace.s,
            ),
            child: Semantics(
              header: true,
              child: Text(title, style: text.title),
            ),
          ),
          for (final c in choices)
            _ChoiceRow(choice: c, selected: c.value == selected),
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.choice, required this.selected});

  final Choice<T> choice;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final style = (choice.labelStyle ?? text.title.withWeight(FontWeight.w500))
        .copyWith(color: selected ? MarqueeColors.bulb : MarqueeColors.cream);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      label: choice.label,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(choice.value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: MarqueeSpace.xxl,
            ),
            child: Row(
              children: [
                Expanded(child: Text(choice.label, style: style)),
                if (selected)
                  const Icon(Icons.check, color: MarqueeColors.bulb, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

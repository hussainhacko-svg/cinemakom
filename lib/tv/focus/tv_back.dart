import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// One rung of the Back ladder (docs/TV.md §5.1 R4): a panel closes, a page
/// pops, a tab's content gives focus to the tab bar, a text field stops
/// editing. [onBack] returns true when it used the press.
///
/// Back is bound once (`tvShortcuts`); [tvHandleBack] asks the handlers from
/// the focused widget outwards. (Flutter's `Shortcuts` stops at the nearest
/// action even when it's disabled, so nested actions can't fall through.)
class TvBack extends StatelessWidget {
  const TvBack({super.key, required this.onBack, required this.child});

  final bool Function() onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Runs the nearest [TvBack] above the focused widget that uses the press;
/// none does: leaves the app (the last rung, §2 open decision: exit at once).
void tvHandleBack() {
  final context = FocusManager.instance.primaryFocus?.context;
  var handled = false;
  context?.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is TvBack && widget.onBack()) {
      handled = true;
      return false;
    }
    return true;
  });
  if (!handled) SystemNavigator.pop();
}

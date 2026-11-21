import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/platform_info.dart';

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

/// Runs the nearest [TvBack] above the focused widget that uses the press.
/// Returns true if a handler consumed the press.
///
/// When no handler takes it (Home tab bar, rung 5):
/// - On Android TV / desktop: exits via `SystemNavigator.pop()`.
/// - On Apple TV: returns `false` without calling `SystemNavigator.pop()` so
///   tvOS natively suspends back to the Apple TV Home Screen.
bool tvHandleBack() {
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
  if (!handled && !isAppleTv) SystemNavigator.pop();
  return handled;
}

import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../focus/tv_back.dart';
import '../focus/tv_focusable.dart';
import '../../app/theme/marquee_text.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';

/// A text field the remote can't fall into (docs/TV.md R8): moving through
/// the screen focuses a button that looks like the field. OK opens the
/// keyboard; Done or Back closes it and gives the arrows back to the zones.
/// Item [index] of its zone.
class TvTextEntry extends StatefulWidget {
  const TvTextEntry({
    super.key,
    required this.index,
    required this.controller,
    required this.label,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.search,
  });

  final int index;
  final TextEditingController controller;

  /// What the field is for ("Search"): its accessible name and hint.
  final String label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<TvTextEntry> createState() => _TvTextEntryState();
}

class _TvTextEntryState extends State<TvTextEntry> {
  final _field = FocusNode(debugLabel: 'TvTextEntry field');
  final _button = GlobalKey();
  bool _editing = false;

  /// The search box design: a 56 dp pill.
  static const double height = 56;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  /// Back to D-pad moves, focus on the box again.
  bool _stop() {
    if (!_editing) return false;
    setState(() => _editing = false);
    final button = _button.currentContext;
    if (button != null) Focus.of(button).requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final value = widget.controller.text;
    // The button stays in the tree while typing, so its zone keeps the item
    // and focus comes back to it.
    return Stack(
      children: [
        TvFocusable(
          index: widget.index,
          label: widget.label,
          onSelect: _start,
          builder: (context, focused) => TvRing(
            on: focused,
            radius: TvRing.pill,
            gap: TvFocusStyle.buttonGap,
            child: Container(
              key: _button,
              height: height,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 22),
              alignment: AlignmentDirectional.centerStart,
              decoration: ShapeDecoration(
                color: focused || _editing
                    ? context.palette.boothRaised
                    : context.palette.booth,
                shape: StadiumBorder(
                  side: BorderSide(color: context.palette.velvetStrong),
                ),
              ),
              child: _editing
                  ? null
                  : Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 22,
                          color: context.palette.cream,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            value.isEmpty ? widget.label : value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.body.copyWith(
                              height: 1.2,
                              color: value.isEmpty
                                  ? context.palette.dust
                                  : context.palette.cream,
                            ),
                          ),
                        ),
                        if (focused)
                          Text(
                            l10n.tvPressOkToType,
                            style: text.caption
                                .withWeight(FontWeight.w600)
                                .copyWith(color: context.palette.bulb),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        if (_editing)
          Positioned.fill(
            child: TvBack(
              onBack: _stop,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(58, 0, 22, 0),
                child: Center(
                  child: TextField(
                    focusNode: _field,
                    controller: widget.controller,
                    textInputAction: widget.textInputAction,
                    style: text.body.copyWith(color: context.palette.cream),
                    cursorColor: context.palette.bulb,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.label,
                    ),
                    onChanged: widget.onChanged,
                    onSubmitted: (v) {
                      _stop();
                      widget.onSubmitted?.call(v);
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

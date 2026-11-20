import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/shell/app_shell.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../core/storage/preferences.dart';
import '../../../data/models/playback_request.dart';
import '../../settings/settings_screen.dart' show subtitleSizeLabel;
import '../player_controller.dart';
import 'controls_overlay.dart' show subtitleLabel, withFocusRing;

/// The player's menus (PLAYER.md §8): a bottom sheet below 600 dp, and from
/// 600 dp a popover under the chip that opened it, so the video stays in
/// view. Playback goes on while a menu is open. [width] is the popover's
/// widest size.
Future<T?> showPlayerMenu<T>(
  BuildContext context, {
  required Rect anchor,
  required WidgetBuilder builder,
  double width = 340,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (MediaQuery.sizeOf(context).width < Breakpoints.rail) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: builder,
    );
  }
  return navigator.push(
    _PopoverRoute<T>(
      anchor: anchor,
      width: width,
      builder: builder,
      textDirection: Directionality.of(context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// Where [context]'s widget sits on screen: the anchor for a popover.
Rect anchorOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.width,
    required this.builder,
    required this.textDirection,
    required this.barrierLabel,
  });

  final Rect anchor;
  final double width;
  final WidgetBuilder builder;
  final TextDirection textDirection;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(
    delegate: _PopoverLayout(
      anchor: anchor,
      width: width,
      textDirection: textDirection,
      padding: MediaQuery.paddingOf(context),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MarqueeColors.booth,
          border: Border.all(color: MarqueeColors.velvet),
          borderRadius: const BorderRadius.all(MarqueeRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MarqueeSpace.m),
          child: Builder(builder: builder),
        ),
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

/// Below the anchor, lined up with its end edge, kept on screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({
    required this.anchor,
    required this.width,
    required this.textDirection,
    required this.padding,
  });

  static const _gap = MarqueeSpace.s;
  static const _margin = MarqueeSpace.l;

  final Rect anchor;
  final double width;
  final TextDirection textDirection;
  final EdgeInsets padding;

  double _top(Size size) {
    final below = anchor.bottom + _gap;
    // Too little room under the anchor (a chip low on the screen): use the
    // whole height instead.
    return size.height - below - _margin - padding.bottom < 200
        ? _margin + padding.top
        : below;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final maxWidth = size.width - 2 * _margin - padding.horizontal;
    return BoxConstraints(
      maxWidth: maxWidth < width ? maxWidth : width,
      maxHeight: size.height - _top(size) - _margin - padding.bottom,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = textDirection == TextDirection.ltr
        ? anchor.right - childSize.width
        : anchor.left;
    final minX = _margin + padding.left;
    final maxX = size.width - _margin - padding.right - childSize.width;
    return Offset(x.clamp(minX, maxX < minX ? minX : maxX), _top(size));
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      anchor != old.anchor ||
      width != old.width ||
      textDirection != old.textDirection ||
      padding != old.padding;
}

// -----------------------------------------------------------------------------
// Menu content

/// A menu's frame: its title, then [children], scrolling when they don't
/// fit.
class PlayerMenu extends StatelessWidget {
  const PlayerMenu({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsetsDirectional.only(bottom: MarqueeSpace.s),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            MarqueeSpace.xl,
            0,
            MarqueeSpace.xl,
            MarqueeSpace.s,
          ),
          child: Semantics(
            header: true,
            child: Text(title, style: MarqueeText.of(context).title),
          ),
        ),
        ...children,
      ],
    ),
  );
}

/// One choice: the current one in `bulb` with a check. [trailing] replaces
/// the check (the "⋯" menu shows each chip's value there).
class MenuRow extends StatefulWidget {
  const MenuRow({
    super.key,
    required this.label,
    required this.onTap,
    this.caption,
    this.selected = false,
    this.autofocus = false,
    this.trailing,
  });

  final String label;
  final String? caption;
  final bool selected;
  final bool autofocus;
  final String? trailing;
  final VoidCallback onTap;

  @override
  State<MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<MenuRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final caption = widget.caption;
    final trailing = widget.trailing;
    return Semantics(
      inMutuallyExclusiveGroup: trailing == null,
      checked: trailing == null ? widget.selected : null,
      button: true,
      excludeSemantics: true,
      label: [widget.label, ?caption, ?trailing].join(', '),
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _focused ? MarqueeColors.boothRaised : null,
            border: _focused
                ? Border.all(color: MarqueeColors.bulb, width: 2)
                : null,
            borderRadius: const BorderRadius.all(MarqueeRadius.thumb),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: MarqueeSpace.xl,
                vertical: MarqueeSpace.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: text.body
                              .withWeight(FontWeight.w500)
                              .copyWith(
                                color: widget.selected
                                    ? MarqueeColors.bulb
                                    : MarqueeColors.cream,
                              ),
                        ),
                        if (caption != null) Text(caption, style: text.caption),
                      ],
                    ),
                  ),
                  if (trailing != null)
                    Text(trailing, style: text.label)
                  else if (widget.selected)
                    const Icon(Icons.check, color: MarqueeColors.bulb, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice of a [ChoiceMenu].
class MenuChoice<T> {
  const MenuChoice(this.value, this.label, {this.caption, this.trailing});

  final T value;
  final String label;
  final String? caption;
  final String? trailing;
}

/// A plain list of choices (quality, speed, fit, "⋯"). Picking one closes
/// the menu with its value.
class ChoiceMenu<T> extends StatelessWidget {
  const ChoiceMenu({
    super.key,
    required this.title,
    required this.choices,
    this.selected,
  });

  final String title;
  final List<MenuChoice<T>> choices;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    final hasSelected =
        selected != null && choices.any((c) => c.value == selected);
    return PlayerMenu(
      title: title,
      children: [
        for (var i = 0; i < choices.length; i++)
          MenuRow(
            label: choices[i].label,
            caption: choices[i].caption,
            trailing: choices[i].trailing,
            selected: choices[i].value == selected,
            autofocus: hasSelected ? choices[i].value == selected : i == 0,
            onTap: () => Navigator.of(context).pop(choices[i].value),
          ),
      ],
    );
  }
}

/// The subtitle menu: the tracks, then (with a track on) the size setting
/// and the Sync stepper. It follows the session live, so the delay and
/// size change in place; picking a track closes it.
class SubtitleMenu extends ConsumerWidget {
  const SubtitleMenu({super.key, required this.request});

  final PlaybackRequest request;

  static const syncStep = Duration(milliseconds: 500);

  /// From this width the size and Sync rows sit beside the tracks.
  static const twoColumnWidth = 520.0;

  /// The popover's width: room for two columns.
  static const popoverWidth = 600.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final provider = playerControllerProvider(request);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final size = ref.watch(settingsProvider.select((s) => s.subtitleSize));
    final delay = state.subtitleDelay;
    // The stepper is laid out LTR; its value reads in the UI's direction.
    final direction = Directionality.of(context);

    Widget heading(String label) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        MarqueeSpace.xl,
        MarqueeSpace.l,
        MarqueeSpace.xl,
        MarqueeSpace.s,
      ),
      child: Text(label, style: text.label.copyWith(color: MarqueeColors.dust)),
    );

    final tracks = [
      for (final o in state.subtitles)
        MenuRow(
          label: subtitleLabel(l10n, o),
          selected: o == state.subtitle,
          autofocus: o == state.subtitle,
          onTap: () {
            controller.selectSubtitle(o);
            // A pick, so the player keeps its controls up (null = dismissed).
            Navigator.of(context).pop(true);
          },
        ),
    ];
    final settings = state.subtitle.isOff
        ? const <Widget>[]
        : [
            heading(l10n.playerSubtitleSize),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: MarqueeSpace.xl,
              ),
              child: Wrap(
                spacing: MarqueeSpace.s,
                runSpacing: MarqueeSpace.s,
                children: [
                  for (final s in SubtitleSize.values)
                    _Pill(
                      label: subtitleSizeLabel(l10n, s),
                      selected: s == size,
                      onTap: () => ref
                          .read(settingsProvider.notifier)
                          .setSubtitleSize(s),
                    ),
                ],
              ),
            ),
            heading(l10n.playerSubtitleSync),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: MarqueeSpace.m,
              ),
              child: Row(
                children: [
                  // A number line: earlier on the left in both languages,
                  // like the seek bar (PLAYER.md §2).
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StepButton(
                          icon: Icons.remove,
                          tooltip: l10n.playerSyncEarlier,
                          onPressed: () =>
                              controller.nudgeSubtitleDelay(-syncStep),
                        ),
                        SizedBox(
                          width: 76,
                          child: Text(
                            l10n.playerSyncSeconds(delayLabel(delay)),
                            textAlign: TextAlign.center,
                            textDirection: direction,
                            style: text.label.copyWith(
                              color: delay == Duration.zero
                                  ? MarqueeColors.cream
                                  : MarqueeColors.bulb,
                            ),
                          ),
                        ),
                        _StepButton(
                          icon: Icons.add,
                          tooltip: l10n.playerSyncLater,
                          onPressed: () =>
                              controller.nudgeSubtitleDelay(syncStep),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: delay == Duration.zero
                        ? null
                        : () => controller.setSubtitleDelay(Duration.zero),
                    style: TextButton.styleFrom(
                      foregroundColor: MarqueeColors.bulb,
                      disabledForegroundColor: MarqueeColors.dustDim,
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(l10n.playerSyncReset),
                  ),
                ],
              ),
            ),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Landscape phones are short: side by side, Sync needs no scroll.
        final twoColumns =
            settings.isNotEmpty && constraints.maxWidth >= twoColumnWidth;
        return PlayerMenu(
          title: l10n.playerSubtitles,
          children: twoColumns
              ? [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: tracks)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: settings,
                        ),
                      ),
                    ],
                  ),
                ]
              : [...tracks, ...settings],
        );
      },
    );
  }
}

/// "+1.5", "0", "−0.5" (Western digits, DESIGN.md §2).
String delayLabel(Duration delay) {
  final ms = delay.inMilliseconds;
  if (ms == 0) return '0';
  final abs = ms.abs() / 1000;
  final digits = abs == abs.roundToDouble()
      ? abs.toStringAsFixed(0)
      : abs.toStringAsFixed(ms % 100 == 0 ? 1 : 2);
  return '${ms > 0 ? '+' : '−'}$digits';
}

/// A filter-chip style pill (DESIGN.md §5).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: TextButton(
      onPressed: onTap,
      style: withFocusRing(
        TextButton.styleFrom(
          backgroundColor: selected ? MarqueeColors.boothRaised : null,
          foregroundColor: selected ? MarqueeColors.cream : MarqueeColors.dust,
          side: BorderSide(
            color: selected ? MarqueeColors.velvetStrong : MarqueeColors.velvet,
          ),
          shape: const StadiumBorder(),
          minimumSize: const Size(44, 36),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: MarqueeSpace.l,
          ),
          textStyle: MarqueeText.of(context).label,
        ),
      ),
      child: Text(label),
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    style: withFocusRing(
      IconButton.styleFrom(
        backgroundColor: MarqueeColors.boothRaised,
        foregroundColor: MarqueeColors.cream,
        side: const BorderSide(color: MarqueeColors.velvet),
        fixedSize: const Size.square(44),
      ),
    ),
  );
}

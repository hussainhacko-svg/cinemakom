import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../theme/tv_space.dart';
import 'tv_screen.dart';

/// Opens a panel from the end edge (docs/TV.md §5.2): every picker uses it.
/// It's modal (R9): focus stays inside, it opens where its initial zone says
/// (the current choice, R11), and Back closes it (R4). When it closes, focus
/// goes back to the control that opened it.
///
/// The panel designs: [width] 400 (360 for the player's short pickers), a
/// `booth` sheet with a `velvet` edge, padded 40 · 48 · 27 · 32 (top, end,
/// bottom, start), over a `night` scrim at [scrim] (72% over a page; 50% over
/// the playing video). [builder] builds the panel's zones; give
/// [ScrollController] to its scroll view so focus scrolls it.
Future<T?> showTvSidePanel<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController scroll)
  builder,
  double width = 400,
  double scrim = 0.72,
}) async {
  final opener = FocusManager.instance.primaryFocus;
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(
    _TvPanelRoute<T>(
      builder: builder,
      width: width,
      scrim: scrim,
      night: context.palette.night,
    ),
  );
  if (opener != null && opener.context != null && opener.canRequestFocus) {
    opener.requestFocus();
  }
  return result;
}

class _TvPanelRoute<T> extends PopupRoute<T> {
  _TvPanelRoute({
    required this.builder,
    required this.width,
    required this.scrim,
    required this.night,
  });

  final Widget Function(BuildContext, ScrollController) builder;
  final double width;
  final double scrim;
  final Color night;

  @override
  Color? get barrierColor => night.withValues(alpha: scrim);

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        width: width,
        height: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(
          32,
          40,
          TvSpace.safeH,
          TvSpace.safeV,
        ),
        decoration: BoxDecoration(
          color: context.palette.booth,
          border: BorderDirectional(
            start: BorderSide(color: context.palette.velvet),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: TvScreen(builder: builder),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = MediaQuery.sizeOf(context).width;
    final from = width == 0 ? 1.0 : (this.width + TvSpace.safeH) / width;
    return SlideTransition(
      position: Tween(
        begin: Offset(rtl ? -from : from, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOut)).animate(animation),
      child: child,
    );
  }
}

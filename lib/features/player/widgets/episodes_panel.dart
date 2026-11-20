import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../app/shell/app_shell.dart' show Breakpoints;
import '../../../app/theme/marquee_colors.dart';
import '../../details/widgets/episode_list.dart';
import '../../../data/models/playback_models.dart';

/// The series' season chips and episode rows, as in Details, to pick
/// another episode without leaving the player (PLAYER.md §7.7). A side
/// panel at the end edge from 600 dp, a bottom sheet below. Returns the
/// picked episode, or `null`.
Future<Episode?> showEpisodesPanel(
  BuildContext context, {
  required String seriesId,
  Episode? current,
}) {
  Widget list(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: MarqueeSpace.xl),
    child: EpisodeList(
      seriesId: seriesId,
      gutter: MarqueeSpace.l,
      initialSeason: current?.season,
      currentId: current?.id,
      autofocusCurrent: true,
      onPlay: (e) => Navigator.of(context).pop(e),
    ),
  );

  final width = MediaQuery.sizeOf(context).width;
  if (width < Breakpoints.rail) {
    return showModalBottomSheet<Episode>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: list,
    );
  }
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return showGeneralDialog<Episode>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x00000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: math.min(420, width * 0.45),
        height: double.infinity,
        child: Material(
          color: MarqueeColors.booth,
          shape: const BorderDirectional(
            start: BorderSide(color: MarqueeColors.velvet),
          ),
          child: SafeArea(child: list(context)),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: Offset(rtl ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
  );
}

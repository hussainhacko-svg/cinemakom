import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/tv/theme/tv_space.dart';
import 'package:cinemakom/tv/widgets/tv_continue_row.dart';
import 'package:cinemakom/tv/widgets/tv_focus_look.dart';
import 'package:cinemakom/tv/widgets/tv_poster_card.dart';

// A focused card grows and gets a ring; its row must leave room for both,
// or the card slides under the next one and its top is cut (seen on the
// TV's Continue watching row, 2026-11-21).
void main() {
  test('a focused Continue watching card fits its row', () {
    final reach = TvCardFocus.reach(
      const Size(TvContinueRow.cardWidth, TvContinueRow.cardHeight),
      TvFocusStyle.wideCardScale,
    );
    expect(reach.side, lessThan(TvContinueRow.gap));
    expect(reach.top, lessThanOrEqualTo(TvContinueRow.topRoom));
  });

  test('a focused poster fits its row', () {
    final reach = TvCardFocus.reach(
      const Size(TvPoster.width, TvPoster.height),
      TvFocusStyle.cardScale,
    );
    expect(reach.side, lessThan(TvPoster.gap));
    expect(reach.top, lessThanOrEqualTo(TvPoster.growRoom));
  });
}

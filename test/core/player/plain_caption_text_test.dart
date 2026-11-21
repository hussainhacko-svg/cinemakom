import 'package:flutter_test/flutter_test.dart';

import 'package:cinemakom/core/player/exo_player_engine.dart';

// SubRip captions on Android (ExoPlayer): video_player keeps their markup,
// and a stray "{\an8}" showed on the TV (2026-11-21).
void main() {
  test('drops SSA override blocks', () {
    expect(plainCaptionText(r'{\an8}ماذا تفعل؟'), 'ماذا تفعل؟');
    expect(plainCaptionText(r'{\i1}Hello{\i0} there'), 'Hello there');
  });

  test('drops HTML-style tags, keeps the text', () {
    expect(plainCaptionText('<i>Run!</i>'), 'Run!');
    expect(
      plainCaptionText('<font color="#ffff00">Yes</font>\n<B>No</B>'),
      'Yes\nNo',
    );
  });

  test('leaves ordinary text alone', () {
    expect(plainCaptionText('a < b, {not a tag}'), 'a < b, {not a tag}');
  });
}

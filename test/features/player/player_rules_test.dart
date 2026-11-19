import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/features/player/quality.dart';
import 'package:cinemakom/features/player/subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSource q(String resolution) =>
    VideoSource(url: 'https://cdn/$resolution.mp4', resolution: resolution);

SubtitleTrack t(String lang, SubtitleFormat format) => SubtitleTrack(
  url: 'https://subs/$lang.${format.name}',
  languageCode: lang,
  format: format,
);

void main() {
  group('pickQuality', () {
    final all = ['2160p', '1080p', '720p', '480p', '360p', '240p'].map(q);

    test('the exact quality, 4K included', () {
      expect(pickQuality(all.toList(), 1080)!.label, '1080p');
      expect(pickQuality(all.toList(), 2160)!.label, '2160p');
    });

    test('else the nearest lower quality', () {
      final no1080 = [q('720p'), q('480p'), q('2160p')];
      expect(pickQuality(no1080, 1080)!.label, '720p');
    });

    test('else the lowest one above', () {
      expect(pickQuality([q('2160p'), q('1080p')], 720)!.label, '1080p');
    });

    test('sources without a height are a last resort', () {
      const odd = VideoSource(url: 'https://cdn/x.mp4', name: 'mp4');
      expect(pickQuality([odd], 1080), odd);
      expect(pickQuality([odd, q('360p')], 1080)!.label, '360p');
      expect(pickQuality([], 1080), isNull);
    });

    test('the chip says 4K for 2160p', () {
      expect(qualityChipLabel(q('2160p')), '4K');
      expect(qualityChipLabel(q('1080p')), '1080p');
    });
  });

  group('subtitles', () {
    final tracks = [
      t('en', SubtitleFormat.vtt),
      t('ar', SubtitleFormat.ass),
      t('ar', SubtitleFormat.vtt),
      t('en', SubtitleFormat.srt),
      t('ar', SubtitleFormat.srt),
    ];

    test('menu: Off, Arabic, English (SRT preferred), then styled', () {
      final options = subtitleOptions(tracks);
      expect(options.first.isOff, isTrue);
      expect(options.skip(1).map((o) => (o.languageCode, o.track!.format)), [
        ('ar', SubtitleFormat.srt),
        ('en', SubtitleFormat.srt),
        ('ar', SubtitleFormat.ass),
      ]);
    });

    test('the default from Settings, plain Arabic over styled', () {
      final options = subtitleOptions(tracks);
      final ar = pickSubtitle(options, SubtitlePreference.arabic);
      expect((ar.languageCode, ar.isStyled), ('ar', false));
      expect(
        pickSubtitle(options, SubtitlePreference.english).languageCode,
        'en',
      );
      expect(pickSubtitle(options, SubtitlePreference.off).isOff, isTrue);
    });

    test('a missing language means Off, never the other language', () {
      final arabicOnly = subtitleOptions([t('ar', SubtitleFormat.srt)]);
      expect(
        pickSubtitle(arabicOnly, SubtitlePreference.english).isOff,
        isTrue,
      );
      final styledOnly = subtitleOptions([t('ar', SubtitleFormat.ass)]);
      expect(pickSubtitle(styledOnly, SubtitlePreference.arabic).isOff, isTrue);
    });

    test('a choice carries over to the next episode by kind', () {
      final styled = subtitleOptions(tracks).last;
      final next = subtitleOptions([
        t('ar', SubtitleFormat.srt),
        t('ar', SubtitleFormat.ass),
      ]);
      expect(carryOver(next, styled)!.isStyled, isTrue);
      expect(
        carryOver(subtitleOptions([t('en', SubtitleFormat.srt)]), styled),
        isNull,
      );
    });
  });
}

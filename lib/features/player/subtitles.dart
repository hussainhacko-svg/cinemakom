import '../../core/storage/preferences.dart';
import '../../data/models/playback_models.dart';

/// One entry of the subtitle menu: off, a plain track, or the styled
/// ("Arabic (styled)") ASS track (PLAYER.md §7.2).
class SubtitleOption {
  const SubtitleOption.off() : track = null;
  const SubtitleOption(SubtitleTrack this.track);

  final SubtitleTrack? track;

  bool get isOff => track == null;
  bool get isStyled => track?.isStyled ?? false;
  String? get languageCode => track?.languageCode;

  /// Same kind of choice in another title (an episode switch keeps it).
  bool sameChoiceAs(SubtitleOption other) =>
      isOff == other.isOff &&
      isStyled == other.isStyled &&
      languageCode == other.languageCode;

  @override
  bool operator ==(Object other) =>
      other is SubtitleOption && other.track?.url == track?.url;

  @override
  int get hashCode => track?.url.hashCode ?? 0;

  @override
  String toString() => isOff ? 'SubtitleOption.off' : 'SubtitleOption($track)';
}

/// The menu: Off, the plain tracks (Arabic, English, then others), then the
/// styled tracks.
List<SubtitleOption> subtitleOptions(List<SubtitleTrack> tracks) {
  int rank(SubtitleTrack t) =>
      (t.isStyled ? 10 : 0) +
      switch (t.languageCode) {
        'ar' => 0,
        'en' => 1,
        _ => 2,
      };
  final picked = oneTrackPerLanguage(tracks)
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  return [
    const SubtitleOption.off(),
    for (final t in picked) SubtitleOption(t),
  ];
}

/// The default choice from Settings. A missing language means Off: never a
/// silent switch to the other language. Plain Arabic stays the default
/// over the styled track.
SubtitleOption pickSubtitle(
  List<SubtitleOption> options,
  SubtitlePreference preference,
) {
  final code = switch (preference) {
    SubtitlePreference.arabic => 'ar',
    SubtitlePreference.english => 'en',
    SubtitlePreference.off => null,
  };
  if (code == null) return const SubtitleOption.off();
  return options.firstWhere(
    (o) => o.languageCode == code && !o.isStyled,
    orElse: () => const SubtitleOption.off(),
  );
}

/// [previous] carried over to a new title's [options], when it has the same
/// kind of track.
SubtitleOption? carryOver(
  List<SubtitleOption> options,
  SubtitleOption previous,
) {
  for (final o in options) {
    if (o.sameChoiceAs(previous)) return o;
  }
  return null;
}

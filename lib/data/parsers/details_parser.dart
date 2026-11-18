import '../../core/json/json_utils.dart';
import '../models/catalog_models.dart';
import '../models/localized_text.dart';
import '../models/media_details.dart';
import 'media_parser.dart';
import 'playback_parser.dart';

/// `allVideoInfo/id/{id}`. `null` when the record has no ID or title.
MediaDetails? parseMediaDetails(Object? json) {
  try {
    final map = asMap(json);
    final item = parseMediaItem(map);
    if (map == null || item == null) return null;
    return MediaDetails(
      item: item,
      directors: parseStaffCredits(map['directorsInfo'], StaffRole.director),
      actors: parseStaffCredits(map['actorsInfo'], StaffRole.actor),
      writers: parseStaffCredits(map['writersInfo'], StaffRole.writer),
      audioLanguages: parseLocalizedList(map['videoLanguages']),
      trailerUrl: _http(readUrl(map, ['trailer', 'trailerUrl'])),
      imdbUrl: _http(readUrl(map, ['imdbUrlRef', 'imdbUrl'])),
      introRanges: parseIntroRanges(map['introSkipping']),
      parentalSkipRanges: parseParentalSkipRanges(map['skippingDurations']),
      views: parseIntLoose(map['videoViewsNumber']),
      likes: parseIntLoose(map['videoLikesNumber'] ?? map['Likes']),
      dislikes: parseIntLoose(map['videoDisLikesNumber'] ?? map['DisLikes']),
      commentCount: parseIntLoose(map['videoCommentsNumber']),
      castable: parseBoolLoose(map['castable']) ?? false,
      subtitles: parseSubtitles(map),
    );
  } catch (_) {
    return null;
  }
}

/// `actorsInfo` / `directorsInfo` / `writersInfo`:
/// `[{nb, name, role, staff_img, staff_img_thumb, staff_img_medium_thumb}]`.
List<StaffCredit> parseStaffCredits(Object? json, StaffRole role) {
  final out = <StaffCredit>[];
  final seen = <String>{};
  for (final entry in asList(json)) {
    final m = asMap(entry);
    if (m == null) continue;
    final id = readId(firstNonBlank(m, ['nb', 'id', 'staffID']));
    final name = firstNonBlank(m, ['name', 'title', 'en_title']);
    if (id == null || name == null || !seen.add(id)) continue;
    out.add(
      StaffCredit(
        id: id,
        name: name,
        role: role,
        imageUrl: _http(
          readUrl(m, [
            'staff_img_medium_thumb',
            'staff_img',
            'staff_img_thumb',
          ]),
        ),
      ),
    );
  }
  return out;
}

/// `introSkipping`: `[{start, end, control_level}]` in seconds.
List<SkipRange> parseIntroRanges(Object? json) {
  final out = <SkipRange>[];
  for (final entry in json is List ? json : [json]) {
    final m = asMap(entry);
    if (m == null) continue;
    final r = _range(m['start'], m['end'], minSeconds: 1);
    if (r != null && !out.contains(r)) out.add(r);
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// `skippingDurations`: `{start: [s1, s2, …], end: [e1, e2, …]}` in seconds.
/// Pairs with a length under half a second (such as the common `0`→`0.1`
/// placeholder) are dropped.
List<SkipRange> parseParentalSkipRanges(Object? json) {
  final m = asMap(json);
  if (m == null) return const [];
  final starts = asList(m['start']);
  final ends = asList(m['end']);
  final out = <SkipRange>[];
  for (var i = 0; i < starts.length && i < ends.length; i++) {
    final r = _range(starts[i], ends[i], minSeconds: 0.5);
    if (r != null && !out.contains(r)) out.add(r);
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// `staff/actorID/{id}/lang/{lang}/level/0`.
StaffPage? parseStaffPage(Object? json) {
  try {
    final m = asMap(json);
    if (m == null) return null;
    final name = firstNonBlank(m, ['title', 'name', 'en_title', 'ar_title']);
    if (name == null) return null;
    return StaffPage(
      name: name,
      role: readString(m['role']),
      imageUrl: _http(
        readUrl(m, ['imgMediumThumbObjUrl', 'imgObjUrl', 'imgThumbObjUrl']),
      ),
      items: parseMediaItems(m['items'] ?? m['videos'] ?? m['data']),
    );
  } catch (_) {
    return null;
  }
}

/// `faqQuestion`, sorted by the server's order.
List<FaqEntry> parseFaq(Object? json) {
  final out = <FaqEntry>[];
  for (final entry in asList(json)) {
    final m = asMap(entry);
    if (m == null) continue;
    final id = readString(m['nb'] ?? m['id']);
    final question = LocalizedText(
      en: readString(m['en_title']),
      ar: readString(m['ar_title']),
    );
    final answer = LocalizedText(
      en: readString(m['en_content']),
      ar: readString(m['ar_content']),
    );
    if (id == null || question.isEmpty || answer.isEmpty) continue;
    out.add(
      FaqEntry(
        id: id,
        question: question,
        answer: answer,
        category: readString(m['categoryName']),
        order: parseIntLoose(m['porder'] ?? m['priority']) ?? 0,
      ),
    );
  }
  return out..sort((a, b) => a.order.compareTo(b.order));
}

SkipRange? _range(Object? start, Object? end, {required double minSeconds}) {
  final s = parseDoubleLoose(start);
  final e = parseDoubleLoose(end);
  if (s == null || e == null || s < 0 || e - s < minSeconds) return null;
  return SkipRange(
    Duration(milliseconds: (s * 1000).round()),
    Duration(milliseconds: (e * 1000).round()),
  );
}

String? _http(String? url) => isHttpUrl(url) ? url : null;

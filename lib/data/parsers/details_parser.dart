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
        imageUrl: _image(m, [
          'staff_img_medium_thumb',
          'staff_img',
          'staff_img_thumb',
        ]),
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

/// `staff/actorID/{id}/lang/{lang}/level/0`: `{title, role, img*ObjUrl,
/// items}`. An unknown person answers `[]` (→ `null`). The image is often
/// the `loadingImages/loading.gif` placeholder, which is dropped.
StaffPage? parseStaffPage(Object? json) {
  try {
    final m = asMap(json);
    if (m == null) return null;
    final name = firstNonBlank(m, ['title', 'name', 'en_title', 'ar_title']);
    if (name == null) return null;
    return StaffPage(
      name: name,
      role: readString(m['role']),
      imageUrl: _image(m, [
        'imgMediumThumbObjUrl',
        'imgObjUrl',
        'imgThumbObjUrl',
      ]),
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
  final from = durationFromSeconds(s);
  final to = durationFromSeconds(e);
  return from == null || to == null ? null : SkipRange(from, to);
}

String? _http(String? url) => isHttpUrl(url) ? url : null;

/// The first real image under [keys] (placeholders are skipped).
String? _image(JsonMap m, List<String> keys) {
  for (final key in keys) {
    final url = realImageUrl(readString(m[key]));
    if (url != null) return url;
  }
  return null;
}

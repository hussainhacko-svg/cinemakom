import '../data/models/media_details.dart';
import '../data/models/media_item.dart';
import '../data/paging/media_sources.dart';

// What a page opens on, shared by the phone and desktop router and the TV's
// (docs/TV.md §4.4): the same paths and arguments in both.

/// What the "See all" screen shows.
class MediaListArgs {
  const MediaListArgs({required this.title, required this.source});

  final String title;
  final MediaSource source;
}

/// What the details screen opens on. [item] is what the list showed, so the
/// header can draw before the full record arrives; a later episode of a
/// series preselects its season.
class TitleArgs {
  const TitleArgs(this.item);

  final MediaItem item;
}

/// What a person's page opens on: the credit that was tapped, so the name,
/// photo and role show before the page loads.
class PersonArgs {
  const PersonArgs(this.credit);

  final StaffCredit credit;
}

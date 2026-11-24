import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_item.dart';
import 'media_sources.dart';

/// The loaded part of a [MediaSource] and what is happening to it.
class PagedMedia {
  const PagedMedia({
    this.items = const [],
    this.next,
    this.isLoading = false,
    this.error,
    this.started = false,
  });

  final List<MediaItem> items;

  /// The next page's cursor; `null` once the end was reached.
  final int? next;
  final bool isLoading;

  /// The error of the last page load, if it failed. Earlier pages stay.
  final Object? error;

  /// False until the first page was requested.
  final bool started;

  bool get hasMore => next != null;

  /// True while nothing has arrived yet (first page loading or not started).
  bool get isFirstLoad => items.isEmpty && (isLoading || !started);

  /// The first page failed: there is nothing to show but the error.
  bool get failedFirstPage => items.isEmpty && error != null && !isLoading;

  /// The end was reached with no titles at all.
  bool get isEmpty => items.isEmpty && started && !hasMore && error == null;

  PagedMedia copyWith({
    List<MediaItem>? items,
    int? Function()? next,
    bool? isLoading,
    Object? Function()? error,
  }) => PagedMedia(
    items: items ?? this.items,
    next: next == null ? this.next : next(),
    isLoading: isLoading ?? this.isLoading,
    error: error == null ? this.error : error(),
    started: true,
  );
}

/// A [MediaSource]'s titles, loaded page by page. The first page loads as
/// soon as something watches it; call [PagedMediaNotifier.loadMore] for the
/// next (lists do this when they near their end). Repeated IDs are dropped,
/// since pages can overlap when the catalog changes while paging.
final pagedMediaProvider = NotifierProvider.autoDispose
    .family<PagedMediaNotifier, PagedMedia, MediaSource>(
      PagedMediaNotifier.new,
    );

class PagedMediaNotifier extends Notifier<PagedMedia> {
  PagedMediaNotifier(this.source);

  final MediaSource source;

  /// How long a list stays loaded after nothing shows it any more, so a
  /// row scrolled off screen and back (or a list left and reopened) doesn't
  /// load again.
  static const keepFor = Duration(minutes: 5);

  /// Pages in a row with titles but none new before the list ends. Every
  /// endpoint answers an empty page past the end, but one repeating its
  /// last page instead would be paged forever (lists load on by themselves
  /// while few titles show). One such page is no end: titles added while
  /// paging can shift a page onto the one before it.
  static const maxRepeatedPages = 2;

  var _repeatedPages = 0;

  @override
  PagedMedia build() {
    final link = ref.keepAlive();
    Timer? timer;
    ref
      ..onCancel(() => timer = Timer(keepFor, link.close))
      ..onResume(() => timer?.cancel())
      ..onDispose(() => timer?.cancel());
    _repeatedPages = 0;
    Future.microtask(loadMore);
    return PagedMedia(next: source.firstCursor);
  }

  /// Loads the next page, unless one is loading, the end was reached, or
  /// the last load failed (use [retry] then).
  Future<void> loadMore() async {
    final cursor = state.next;
    if (!ref.mounted || state.isLoading || cursor == null) return;
    if (state.started && state.error != null) return;
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final page = await source.load(ref, cursor);
      if (!ref.mounted) return;
      final seen = {for (final i in state.items) i.id};
      final fresh = [
        for (final i in page.items)
          if (seen.add(i.id)) i,
      ];
      _repeatedPages = page.items.isNotEmpty && fresh.isEmpty
          ? _repeatedPages + 1
          : 0;
      final ended = _repeatedPages >= maxRepeatedPages;
      state = state.copyWith(
        items: [...state.items, ...fresh],
        next: () => ended ? null : page.next,
        isLoading: false,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: () => e);
    }
  }

  /// Clears the last error and loads the failed page again.
  Future<void> retry() async {
    state = state.copyWith(error: () => null);
    await loadMore();
  }
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/preferences.dart';

/// How many recent searches are kept.
const searchHistoryLimit = 10;

/// The recent searches on this device, newest first, without duplicates
/// (case-insensitive). Kept in the preference store as a JSON list.
final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );

class SearchHistoryNotifier extends Notifier<List<String>> {
  PreferenceStore get _store => ref.read(preferenceStoreProvider).requireValue;

  @override
  List<String> build() {
    final raw = ref
        .watch(preferenceStoreProvider)
        .requireValue
        .getString(PreferenceKeys.searchHistory);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final q in list)
          if (q is String && q.trim().isNotEmpty) q.trim(),
      ].take(searchHistoryLimit).toList();
    } on FormatException {
      return const [];
    }
  }

  /// Puts [query] first, dropping an older copy of it.
  Future<void> add(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value();
    final key = q.toLowerCase();
    return _save(
      [
        q,
        ...state.where((s) => s.toLowerCase() != key),
      ].take(searchHistoryLimit).toList(),
    );
  }

  Future<void> remove(String query) =>
      _save([...state.where((s) => s != query)]);

  Future<void> clear() => _save(const []);

  Future<void> _save(List<String> list) {
    state = list;
    return _store.setString(PreferenceKeys.searchHistory, jsonEncode(list));
  }
}

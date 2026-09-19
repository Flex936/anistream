import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../data/anilist/anilist_query_service.dart';
import '../../../data/anilist/models/media_list.dart';

/// Sort orders offered on the Watchlist screen. Each maps to real
/// AniList `MediaListSort` enum values that `WatchlistController` passes
/// straight through to `AnilistQueryService.getUserWatchlist` — sorting
/// happens server-side, so pagination always returns entries already in
/// the chosen order instead of a client-side re-sort that would drift
/// once more pages load.
enum WatchlistSortOption {
  titleAsc,
  scoreDesc,
  progressDesc,
  recentlyUpdated,
  recentlyAdded,
}

extension WatchlistSortOptionLabel on WatchlistSortOption {
  String get label => switch (this) {
    WatchlistSortOption.titleAsc => 'Title (A–Z)',
    WatchlistSortOption.scoreDesc => 'Score (High–Low)',
    WatchlistSortOption.progressDesc => 'Progress (High–Low)',
    WatchlistSortOption.recentlyUpdated => 'Recently Updated',
    WatchlistSortOption.recentlyAdded => 'Recently Added',
  };

  List<String> get anilistSort => switch (this) {
    WatchlistSortOption.titleAsc => const [
      'MEDIA_TITLE_ROMAJI',
      'MEDIA_ID_DESC',
    ],
    WatchlistSortOption.scoreDesc => const [
      'SCORE_DESC',
      'MEDIA_TITLE_ROMAJI',
    ],
    WatchlistSortOption.progressDesc => const [
      'PROGRESS_DESC',
      'MEDIA_TITLE_ROMAJI',
    ],
    WatchlistSortOption.recentlyUpdated => const ['UPDATED_TIME_DESC'],
    WatchlistSortOption.recentlyAdded => const ['ADDED_TIME_DESC'],
  };
}

class _TabState {
  List<MediaListEntry> entries = [];
  int page = 1;
  bool hasNext = true;
  bool loading = true;
  String? error;
}

/// Owns the CURRENT/PLANNING/COMPLETED tab data, pagination, sort order,
/// and dedup-by-id fetch logic for `WatchlistScreen`.
class WatchlistController extends ChangeNotifier {
  final AnilistQueryService _api;
  WatchlistController({AnilistQueryService? api})
    : _api = api ?? AnilistQueryService();

  static const statuses = ['CURRENT', 'PLANNING', 'COMPLETED'];
  final Map<String, _TabState> _tabs = {
    for (final s in statuses) s: _TabState(),
  };

  String activeStatus = 'CURRENT';

  /// Applies across every tab, not scoped to whichever one is active —
  /// see [changeSort]. Resets to title order each session rather than
  /// persisting, unlike `WatchlistScreen`'s own list/grid view-mode
  /// preference.
  WatchlistSortOption sortOption = WatchlistSortOption.titleAsc;

  List<MediaListEntry> get activeEntries => _tabs[activeStatus]!.entries;
  bool get isInitialLoading =>
      _tabs[activeStatus]!.loading && _tabs[activeStatus]!.entries.isEmpty;
  bool get isFetchingNext =>
      _tabs[activeStatus]!.loading && _tabs[activeStatus]!.entries.isNotEmpty;
  String? get error => _tabs[activeStatus]!.error;
  bool get hasNext => _tabs[activeStatus]!.hasNext;

  Future<void> loadInitial() => fetchTab(activeStatus);

  void switchTab(String status) {
    if (activeStatus == status) return;
    activeStatus = status;
    notifyListeners();
    if (_tabs[status]!.entries.isEmpty && _tabs[status]!.hasNext) {
      unawaited(fetchTab(status));
    }
  }

  Future<void> fetchNextForActiveTab() {
    final tab = _tabs[activeStatus]!;
    if (tab.loading || !tab.hasNext) return Future.value();
    return fetchTab(activeStatus);
  }

  Future<void> refreshActiveTab() {
    _tabs[activeStatus] = _TabState();
    return fetchTab(activeStatus);
  }

  /// Applies [option] as the sort for every tab and refetches the active
  /// one from page 1. Every tab's pagination state is reset here, not
  /// just the active tab's — an inactive tab still holding entries
  /// fetched under the previous sort would otherwise show stale order
  /// the moment [switchTab] brings it back on screen, since that method
  /// only fetches a tab whose entries are still empty.
  Future<void> changeSort(WatchlistSortOption option) {
    if (sortOption == option) return Future.value();
    sortOption = option;
    for (final status in statuses) {
      _tabs[status] = _TabState();
    }
    return fetchTab(activeStatus);
  }

  Future<void> fetchTab(String status) async {
    final tab = _tabs[status]!;
    if (!tab.hasNext) return;

    tab.loading = true;
    tab.error = null;
    notifyListeners();

    try {
      final result = await _api.getUserWatchlist(
        status: status,
        page: tab.page,
        perPage: 36,
        sort: sortOption.anilistSort,
      );
      final existingIds = tab.entries.map((e) => e.media.id).toSet();
      tab.entries.addAll(
        result.entries.where((e) => !existingIds.contains(e.media.id)),
      );
      tab.hasNext = result.hasNextPage;
      tab.page += 1;
      tab.loading = false;
      notifyListeners();
    } catch (e) {
      tab.error = e.toString();
      tab.loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
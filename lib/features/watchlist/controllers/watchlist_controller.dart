import 'package:flutter/foundation.dart';
import '../../../data/anilist/anilist_query_service.dart';
import '../../../data/anilist/models/media_list.dart';

class _TabState {
  List<MediaListEntry> entries = [];
  int page = 1;
  bool hasNext = true;
  bool loading = true;
  String? error;
}

/// Extracted from `_WatchlistScreenState`: owns the CURRENT/PLANNING/
/// COMPLETED tab data, pagination, and dedup-by-id fetch logic that used to
/// live as three parallel `Map<String, ...>` fields on the State.
class WatchlistController extends ChangeNotifier {
  final AnilistQueryService _api;
  WatchlistController({AnilistQueryService? api})
    : _api = api ?? AnilistQueryService();

  static const statuses = ['CURRENT', 'PLANNING', 'COMPLETED'];
  final Map<String, _TabState> _tabs = {
    for (final s in statuses) s: _TabState(),
  };

  String activeStatus = 'CURRENT';

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
      fetchTab(status);
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

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/awareness_article.dart';
import '../../data/services/awareness_feed_service.dart';

class AwarenessFeedController extends ChangeNotifier {
  AwarenessFeedController({AwarenessFeedService? service})
    : _service = service {
    _backgroundSubscription = service?.backgroundUpdates.listen((_) {
      _applyBackgroundUpdate();
    });
  }

  final AwarenessFeedService? _service;
  StreamSubscription<void>? _backgroundSubscription;

  String? _userId;
  List<AwarenessArticle> _articles = const [];
  AwarenessScope _scope = AwarenessScope.forYou;
  AwarenessCategory? _category;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  DateTime? _lastUpdatedAt;
  String? _backgroundUpdateMessage;
  int _generation = 0;
  bool _disposed = false;

  List<AwarenessArticle> get articles => List.unmodifiable(_articles);
  AwarenessScope get scope => _scope;
  AwarenessCategory? get category => _category;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  String? get backgroundUpdateMessage => _backgroundUpdateMessage;

  AwarenessArticle? get featured => _articles.isEmpty ? null : _articles.first;

  Future<void> bindAuthenticatedUser(String? userId) async {
    if (_disposed) return;
    if (_userId == userId) {
      return;
    }
    _userId = userId;
    _generation++;
    _articles = const [];
    _hasLoaded = false;
    _isLoading = false;
    _isRefreshing = false;
    _errorMessage = null;
    _lastUpdatedAt = null;
    _backgroundUpdateMessage = null;
    if (userId != null) {
      await refresh();
    } else {
      notifyListeners();
    }
  }

  Future<void> setScope(AwarenessScope value) async {
    if (_scope == value) {
      return;
    }
    _scope = value;
    await refresh(refreshIfStale: false);
  }

  Future<void> setCategory(AwarenessCategory? value) async {
    if (_category == value) {
      return;
    }
    _category = value;
    await refresh(refreshIfStale: false);
  }

  Future<void> refresh({bool refreshIfStale = true}) async {
    final service = _service;
    final userId = _userId;
    if (service == null || userId == null || _isLoading) {
      return;
    }

    final generation = ++_generation;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loaded = await service.fetchFeed(
        scope: _scope,
        category: _category,
        refreshIfStale: refreshIfStale,
      );
      if (!_isCurrent(userId, generation)) {
        return;
      }
      _articles = loaded;
      _hasLoaded = true;
      _lastUpdatedAt = _displayedDataTimestamp(loaded);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Awareness refresh failed: $error\n$stackTrace');
      }
      if (!_isCurrent(userId, generation)) {
        return;
      }
      _hasLoaded = true;
      _errorMessage = _friendlyMessage(error);
    } finally {
      if (_isCurrent(userId, generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> forceRefresh() async {
    final service = _service;
    final userId = _userId;
    if (service == null || userId == null || _isRefreshing || _disposed) {
      return false;
    }
    final generation = ++_generation;
    _isRefreshing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await service.forceRefresh();
      final loaded = await service.fetchFeed(
        scope: _scope,
        category: _category,
        refreshIfStale: false,
        forceDatabaseRead: true,
      );
      if (!_isCurrent(userId, generation)) return false;
      _articles = loaded;
      _hasLoaded = true;
      _lastUpdatedAt =
          service.lastSuccessfulRefreshAt ?? _displayedDataTimestamp(loaded);
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Awareness force refresh failed: $error\n$stackTrace');
      }
      if (_isCurrent(userId, generation)) {
        _errorMessage = _friendlyMessage(error);
      }
      return false;
    } finally {
      if (_isCurrent(userId, generation)) {
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  /// Learner-safe manual check. This always asks the Edge Function whether
  /// the shared Awareness cache is stale, instead of being satisfied by the
  /// short-lived Flutter cache. The server still controls whether an external
  /// source scan is needed, so repeated learner clicks do not bypass traffic
  /// limits or the global refresh interval.
  Future<String> checkForUpdates() async {
    final service = _service;
    final userId = _userId;

    if (service == null || userId == null) {
      return 'Please sign in again to continue.';
    }

    if (_isRefreshing) {
      return 'An update check is already running.';
    }

    final generation = ++_generation;
    final scope = _scope;
    final category = _category;
    _isRefreshing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final message = await service.checkForUpdates();
      final loaded = await service.fetchFeed(
        scope: scope,
        category: category,
        refreshIfStale: false,
        forceDatabaseRead: true,
      );
      if (!_isCurrent(userId, generation)) {
        return 'The account changed before the update check completed.';
      }
      _articles = loaded;
      _hasLoaded = true;
      _lastUpdatedAt =
          service.lastSuccessfulRefreshAt ?? _displayedDataTimestamp(loaded);

      return message.trim().isEmpty
          ? 'AI Awareness is up to date.'
          : message.trim();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Awareness update check failed: $error\n$stackTrace');
      }
      if (!_isCurrent(userId, generation)) {
        return 'The account changed before the update check completed.';
      }
      final message = _friendlyMessage(error);
      _errorMessage = message;
      return message;
    } finally {
      if (_isCurrent(userId, generation)) {
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> ensureCurrentSources() async {
    final service = _service;
    final userId = _userId;
    if (service == null || userId == null || _disposed) {
      return false;
    }

    // Verification Studio does not need to block on another internet refresh
    // when the shared Awareness controller already has a recent trusted item.
    // This also avoids a race where an in-flight refresh made the method return
    // false even though usable cached articles were already on screen.
    if (_hasUsableCurrentSource()) {
      return true;
    }
    if (_isRefreshing) {
      return _hasUsableCurrentSource();
    }

    _isRefreshing = true;
    final generation = ++_generation;
    _errorMessage = null;
    notifyListeners();
    try {
      await service.ensureCurrentSources();
      final loaded = await service.fetchFeed(
        scope: _scope,
        category: _category,
        refreshIfStale: false,
        forceDatabaseRead: true,
      );
      if (!_isCurrent(userId, generation)) return false;
      _articles = loaded;
      _hasLoaded = true;
      _lastUpdatedAt = _displayedDataTimestamp(loaded);
      if (_hasUsableCurrentSource()) {
        return true;
      }
      _errorMessage ??=
          'No recent trusted Awareness article is available for Verify yet.';
      return false;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Awareness source check failed: $error\n$stackTrace');
      }
      if (!_isCurrent(userId, generation)) return false;
      _errorMessage = _friendlyMessage(error);
      return _hasUsableCurrentSource();
    } finally {
      if (_isCurrent(userId, generation)) {
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  bool _hasUsableCurrentSource() {
    final now = DateTime.now();
    for (final article in _articles) {
      if (article.sourceUrl.trim().isEmpty || article.trustLevel < 70) {
        continue;
      }
      final stamp = article.discoveredAt ?? article.publishedAt;
      if (stamp == null) {
        return true;
      }
      final age = now.difference(stamp);
      if (!age.isNegative && age <= const Duration(days: 21)) {
        return true;
      }
    }
    return false;
  }

  DateTime? _displayedDataTimestamp(List<AwarenessArticle> articles) {
    DateTime? latest;
    for (final article in articles) {
      final stamp = article.discoveredAt ?? article.publishedAt;
      if (stamp != null && (latest == null || stamp.isAfter(latest))) {
        latest = stamp;
      }
    }
    return latest;
  }

  Future<void> _applyBackgroundUpdate() async {
    final userId = _userId;
    if (userId == null || _isLoading || _isRefreshing) return;
    final generation = _generation;
    await refresh(refreshIfStale: false);
    if (!_disposed &&
        _userId == userId &&
        _generation == generation + 1 &&
        _errorMessage == null) {
      _backgroundUpdateMessage = 'New awareness updates were loaded.';
      notifyListeners();
    }
  }

  void clearBackgroundUpdateMessage() {
    if (_backgroundUpdateMessage == null) return;
    _backgroundUpdateMessage = null;
    notifyListeners();
  }

  Future<void> markRead(AwarenessArticle article) async {
    if (article.read) {
      return;
    }
    final userId = _userId;
    final generation = _generation;
    try {
      await _service?.markRead(article.id);
      if (userId == null || !_isCurrent(userId, generation)) return;
      _replace(article.copyWith(read: true));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Awareness read tracking failed: $error\n$stackTrace');
      }
      // Reading an article must still work if progress bookkeeping fails.
    }
  }

  Future<void> toggleSaved(AwarenessArticle article) async {
    final next = !article.saved;
    final userId = _userId;
    final generation = _generation;
    try {
      await _service?.setSaved(article.id, next);
      if (userId == null || !_isCurrent(userId, generation)) return;
      _replace(article.copyWith(saved: next));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Awareness saved-state update failed: $error\n$stackTrace');
      }
      if (userId != null && _isCurrent(userId, generation)) {
        _errorMessage = _friendlyMessage(error);
        notifyListeners();
      }
    }
  }

  void _replace(AwarenessArticle replacement) {
    final index = _articles.indexWhere((item) => item.id == replacement.id);
    if (index < 0) {
      return;
    }
    final copy = [..._articles];
    copy[index] = replacement;
    _articles = List.unmodifiable(copy);
    notifyListeners();
  }

  String _friendlyMessage(Object error) {
    final raw = error is AwarenessFeedException
        ? error.message.trim()
        : error.toString().trim();
    final value = raw.toLowerCase();
    if (value.contains('sign in') ||
        value.contains('authentication required')) {
      return 'Please sign in again to continue.';
    }
    if (value.contains('failed to fetch') ||
        value.contains('socket') ||
        value.contains('network') ||
        value.contains('timeout') ||
        value.contains('aborted')) {
      return 'Live awareness updates could not be reached. Check your connection and try again.';
    }

    if (raw.isNotEmpty && raw.length <= 260) {
      return raw;
    }
    return 'AI Awareness could not be updated right now.';
  }

  bool _isCurrent(String userId, int generation) {
    return !_disposed && _userId == userId && _generation == generation;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _backgroundSubscription?.cancel();
    _service?.dispose();
    super.dispose();
  }
}

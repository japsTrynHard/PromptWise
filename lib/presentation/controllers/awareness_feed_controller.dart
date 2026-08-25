import 'package:flutter/foundation.dart';

import '../../data/models/awareness_article.dart';
import '../../data/services/awareness_feed_service.dart';

class AwarenessFeedController extends ChangeNotifier {
  AwarenessFeedController({AwarenessFeedService? service}) : _service = service;

  final AwarenessFeedService? _service;

  String? _userId;
  List<AwarenessArticle> _articles = const [];
  AwarenessScope _scope = AwarenessScope.forYou;
  AwarenessCategory? _category;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  DateTime? _lastUpdatedAt;
  int _generation = 0;

  List<AwarenessArticle> get articles => List.unmodifiable(_articles);
  AwarenessScope get scope => _scope;
  AwarenessCategory? get category => _category;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  AwarenessArticle? get featured => _articles.isEmpty ? null : _articles.first;

  Future<void> bindAuthenticatedUser(String? userId) async {
    if (_userId == userId) {
      return;
    }
    _userId = userId;
    _generation++;
    _articles = const [];
    _hasLoaded = false;
    _errorMessage = null;
    _lastUpdatedAt = null;
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
      if (generation != _generation || _userId != userId) {
        return;
      }
      _articles = loaded;
      _hasLoaded = true;
      _lastUpdatedAt = DateTime.now();
    } catch (error) {
      if (generation != _generation || _userId != userId) {
        return;
      }
      _hasLoaded = true;
      _errorMessage = _friendlyMessage(error);
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> forceRefresh() async {
    final service = _service;
    if (service == null || _userId == null || _isRefreshing) {
      return false;
    }
    _isRefreshing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await service.forceRefresh();
      await refresh(refreshIfStale: false);
      return true;
    } catch (error) {
      _errorMessage = _friendlyMessage(error);
      return false;
    } finally {
      _isRefreshing = false;
      notifyListeners();
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

    _isRefreshing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final message = await service.checkForUpdates();

      // Re-read Supabase after the server-side stale check so newly discovered
      // articles become visible immediately. This bypasses only the local
      // Flutter cache; it does not force another external source scan.
      await refresh(refreshIfStale: false);

      if (_userId == userId) {
        _lastUpdatedAt = DateTime.now();
      }

      return message.trim().isEmpty
          ? 'AI Awareness is up to date.'
          : message.trim();
    } catch (error) {
      final message = _friendlyMessage(error);
      _errorMessage = message;
      return message;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<bool> ensureCurrentSources() async {
    final service = _service;
    if (service == null || _userId == null) {
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
    _errorMessage = null;
    notifyListeners();
    try {
      await service.ensureCurrentSources();
      await refresh(refreshIfStale: false);
      if (_hasUsableCurrentSource()) {
        return true;
      }
      _errorMessage ??=
          'No recent trusted Awareness article is available for Verify yet.';
      return false;
    } catch (error) {
      _errorMessage = _friendlyMessage(error);
      return _hasUsableCurrentSource();
    } finally {
      _isRefreshing = false;
      notifyListeners();
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

  Future<void> markRead(AwarenessArticle article) async {
    if (article.read) {
      return;
    }
    try {
      await _service?.markRead(article.id);
      _replace(article.copyWith(read: true));
    } catch (_) {
      // Reading an article must still work if progress bookkeeping fails.
    }
  }

  Future<void> toggleSaved(AwarenessArticle article) async {
    final next = !article.saved;
    try {
      await _service?.setSaved(article.id, next);
      _replace(article.copyWith(saved: next));
    } catch (error) {
      _errorMessage = _friendlyMessage(error);
      notifyListeners();
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
    if (value.contains('sign in') || value.contains('authentication required')) {
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

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}

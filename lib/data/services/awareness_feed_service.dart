import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../models/awareness_article.dart';

class AwarenessFeedService {
  AwarenessFeedService({
    required SupabaseClient client,
    http.Client? httpClient,
  }) : _client = client,
       _http = httpClient ?? http.Client();

  static const Duration _cacheTtl = Duration(minutes: 5);
  static const Duration _staleCheckThrottle = Duration(minutes: 30);

  final SupabaseClient _client;
  final http.Client _http;

  List<AwarenessArticle> _cache = const [];
  String? _cacheUserId;
  DateTime? _cacheFetchedAt;
  DateTime? _lastStaleCheckAt;
  bool _backgroundRefreshRunning = false;

  Future<List<AwarenessArticle>> fetchFeed({
    AwarenessScope scope = AwarenessScope.forYou,
    AwarenessCategory? category,
    int limit = 80,
    bool refreshIfStale = true,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AwarenessFeedException('Please sign in again to continue.');
    }

    _bindCacheUser(userId);
    final now = DateTime.now();
    if (_cache.isNotEmpty &&
        _cacheFetchedAt != null &&
        now.difference(_cacheFetchedAt!) < _cacheTtl) {
      if (refreshIfStale) {
        _scheduleRefreshIfStale();
      }
      return _filteredCache(scope: scope, category: category, limit: limit);
    }

    Object? refreshFailure;

    // Cached-first: read Supabase rows immediately. Do not make the learner wait
    // for an external news refresh when usable cached articles already exist.
    final cached = await _loadCacheFromDatabase(userId);
    if (cached.isNotEmpty) {
      _cache = cached;
      _cacheFetchedAt = DateTime.now();
      if (refreshIfStale) {
        _scheduleRefreshIfStale();
      }
      return _filteredCache(scope: scope, category: category, limit: limit);
    }

    // First-run/empty-cache path: only here do we block on online discovery.
    if (refreshIfStale) {
      try {
        await _refreshIfStale();
      } catch (error) {
        refreshFailure = error;
      }

      final refreshed = await _loadCacheFromDatabase(userId);
      if (refreshed.isNotEmpty) {
        _cache = refreshed;
        _cacheFetchedAt = DateTime.now();
        return _filteredCache(scope: scope, category: category, limit: limit);
      }
    }

    if (refreshFailure != null) {
      if (refreshFailure is AwarenessFeedException) {
        throw refreshFailure;
      }
      throw AwarenessFeedException(refreshFailure.toString());
    }

    _cache = const [];
    _cacheFetchedAt = DateTime.now();
    return const [];
  }

  Future<List<AwarenessArticle>> _loadCacheFromDatabase(String userId) async {
    // Newer databases expose a single joined RPC so article rows and this
    // learner's read/saved flags arrive in one round trip. Fall back to the
    // legacy two-query path until the traffic migration is applied.
    try {
      final response = await _client.rpc(
        'get_my_awareness_feed_cache',
        params: const {'p_limit': 80},
      );
      final rows = response is List
          ? response
          : response is Map && response['items'] is List
              ? response['items'] as List
              : const <dynamic>[];
      if (rows.isNotEmpty) {
        return _mapAwarenessRows(rows);
      }
    } on PostgrestException catch (error) {
      final code = (error.code ?? '').toUpperCase();
      final text = error.message.toLowerCase();
      final missingRpc = code == 'PGRST202' ||
          code == '42883' ||
          (text.contains('function') && text.contains('does not exist'));
      if (!missingRpc) {
        rethrow;
      }
    }

    return _loadCacheFromDatabaseLegacy(userId);
  }

  Future<List<AwarenessArticle>> _loadCacheFromDatabaseLegacy(
    String userId,
  ) async {
    final response = await _client
        .from('awareness_articles')
        .select(
          'id,title,summary,why_it_matters,source_name,source_domain,source_url,'
          'image_url,published_at,discovered_at,category,region,relevance_score,trust_level,ai_relevance_score',
        )
        .eq('is_active', true)
        .gte('ai_relevance_score', 4)
        .order('relevance_score', ascending: false)
        .order('published_at', ascending: false)
        .limit(80);

    final rows = response as List;
    if (rows.isEmpty) {
      return const [];
    }

    final articleIds = rows
        .whereType<Map>()
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final actions = <String, Map<String, dynamic>>{};
    if (articleIds.isNotEmpty) {
      final actionRows = await _client
          .from('awareness_user_actions')
          .select('article_id,read_at,saved_at')
          .eq('user_id', userId)
          .inFilter('article_id', articleIds);
      for (final raw in actionRows as List) {
        if (raw is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(raw);
        final articleId = map['article_id']?.toString();
        if (articleId != null) {
          actions[articleId] = map;
        }
      }
    }

    final joined = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final action = actions[map['id']?.toString()];
      map['read'] = action?['read_at'] != null;
      map['saved'] = action?['saved_at'] != null;
      joined.add(map);
    }
    return _mapAwarenessRows(joined);
  }

  List<AwarenessArticle> _mapAwarenessRows(List<dynamic> rows) {
    final articles = <AwarenessArticle>[];
    for (final raw in rows) {
      if (raw is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final article = AwarenessArticle.fromMap(map);
      if (article.id.isEmpty ||
          article.title.isEmpty ||
          article.sourceUrl.isEmpty) {
        continue;
      }
      // Defense in depth for older cached rows. The server is authoritative,
      // but the learner feed should never show a generic scam/fake-news story
      // just because it was cached before the AI-only Phase 9 filter existed.
      if (!_isAiAwarenessArticle(article)) {
        continue;
      }
      articles.add(article);
    }
    return List.unmodifiable(articles);
  }

  List<AwarenessArticle> _filteredCache({
    required AwarenessScope scope,
    required AwarenessCategory? category,
    required int limit,
  }) {
    final items = _cache.where((item) {
      if (scope == AwarenessScope.philippines && !item.isPhilippines) {
        return false;
      }
      if (category != null && item.category != category) {
        return false;
      }
      return true;
    }).toList(growable: false);

    if (scope == AwarenessScope.latest) {
      items.sort((a, b) {
        final aDate = a.publishedAt ?? a.discoveredAt ?? DateTime(2000);
        final bDate = b.publishedAt ?? b.discoveredAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });
    } else {
      items.sort((a, b) {
        final relevance = b.relevanceScore.compareTo(a.relevanceScore);
        if (relevance != 0) {
          return relevance;
        }
        final aDate = a.publishedAt ?? a.discoveredAt ?? DateTime(2000);
        final bDate = b.publishedAt ?? b.discoveredAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });
    }

    final safeLimit = limit.clamp(10, 80).toInt();
    return List.unmodifiable(items.take(safeLimit).toList());
  }

  void _scheduleRefreshIfStale() {
    final now = DateTime.now();
    if (_backgroundRefreshRunning) {
      return;
    }
    if (_lastStaleCheckAt != null &&
        now.difference(_lastStaleCheckAt!) < _staleCheckThrottle) {
      return;
    }
    _lastStaleCheckAt = now;
    _backgroundRefreshRunning = true;
    unawaited(
      _refreshIfStale()
          .then((refreshed) {
            // Only force a database reread when the Edge Function actually
            // changed the server cache. A normal no-op stale check stays free.
            if (refreshed) {
              _cacheFetchedAt = null;
            }
          })
          .catchError((_) {
            // Existing cached articles stay usable if discovery is temporarily down.
          })
          .whenComplete(() {
            _backgroundRefreshRunning = false;
          }),
    );
  }

  void _bindCacheUser(String userId) {
    if (_cacheUserId == userId) {
      return;
    }
    _cacheUserId = userId;
    _cache = const [];
    _cacheFetchedAt = null;
    _lastStaleCheckAt = null;
  }

  void _invalidateCache() {
    _cache = const [];
    _cacheFetchedAt = null;
  }

  Future<void> markRead(String articleId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || articleId.isEmpty) {
      return;
    }
    await _client.from('awareness_user_actions').upsert(
      {
        'user_id': userId,
        'article_id': articleId,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,article_id',
    );
    _cache = _cache
        .map((item) => item.id == articleId ? item.copyWith(read: true) : item)
        .toList(growable: false);
  }

  Future<void> setSaved(String articleId, bool saved) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || articleId.isEmpty) {
      return;
    }
    await _client.from('awareness_user_actions').upsert(
      {
        'user_id': userId,
        'article_id': articleId,
        'saved_at': saved ? DateTime.now().toUtc().toIso8601String() : null,
      },
      onConflict: 'user_id,article_id',
    );
    _cache = _cache
        .map((item) => item.id == articleId ? item.copyWith(saved: saved) : item)
        .toList(growable: false);
  }

  Future<String> forceRefresh() async {
    final result = await _invokeRefresh(action: 'force_refresh');
    if (result.refreshed) {
      _invalidateCache();
    }
    _lastStaleCheckAt = DateTime.now();
    return result.message;
  }

  Future<String> checkForUpdates() async {
    final result = await _invokeRefresh(action: 'manual_check');
    if (result.refreshed) {
      _invalidateCache();
    } else {
      // A manual check must still reread Supabase because another client or the
      // scheduled collector may have populated new rows since this Flutter
      // cache was created.
      _cacheFetchedAt = null;
    }
    _lastStaleCheckAt = DateTime.now();
    return result.message;
  }

  Future<String> ensureCurrentSources() async {
    final result = await _invokeRefresh(action: 'refresh_if_stale');

    // The Edge Function may report a provider warning while the database still
    // contains perfectly usable cached trusted articles. Verify generation can
    // safely use those rows, so confirm the database cache before failing.
    if (result.warning != null && result.activeCount <= 0) {
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        final cached = await _loadCacheFromDatabase(userId);
        if (cached.isNotEmpty) {
          _cache = cached;
          _cacheFetchedAt = DateTime.now();
          _lastStaleCheckAt = DateTime.now();
          return 'Using the most recently saved trusted Awareness updates.';
        }
      }
      throw AwarenessFeedException(result.warning!);
    }

    if (result.refreshed) {
      _invalidateCache();
    }
    _lastStaleCheckAt = DateTime.now();
    return result.message;
  }

  Future<bool> _refreshIfStale() async {
    final result = await _invokeRefresh(action: 'refresh_if_stale');
    if (result.warning != null && result.activeCount <= 0) {
      throw AwarenessFeedException(result.warning!);
    }
    return result.refreshed;
  }

  Future<_AwarenessRefreshResult> _invokeRefresh({required String action}) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AwarenessFeedException('Please sign in again to continue.');
    }

    final uri = Uri.parse(
      '${AppEnvironment.supabaseUrl}/functions/v1/awareness-feed',
    );
    final response = await _http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': AppEnvironment.supabasePublishableKey,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'action': action}),
        )
        .timeout(const Duration(seconds: 35));

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['error']?.toString() ?? decoded['message']?.toString()
          : null;
      throw AwarenessFeedException(
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'Awareness updates could not be refreshed right now.',
      );
    }
    if (decoded is Map) {
      final warning = decoded['warning']?.toString().trim();
      final activeCount =
          int.tryParse(decoded['activeCount']?.toString() ?? '') ?? 0;
      final success = decoded['success'] == true;
      final message =
          decoded['message']?.toString().trim() ?? 'Awareness feed refreshed.';
      if (!success && warning?.isNotEmpty == true && activeCount <= 0) {
        throw AwarenessFeedException(warning!);
      }
      return _AwarenessRefreshResult(
        message: message,
        warning: warning?.isNotEmpty == true ? warning : null,
        activeCount: activeCount,
        refreshed: decoded['refreshed'] == true,
      );
    }
    return const _AwarenessRefreshResult(
      message: 'Awareness feed refreshed.',
      activeCount: 0,
      refreshed: false,
    );
  }

  void dispose() => _http.close();
}

bool _isAiAwarenessArticle(AwarenessArticle article) {
  final text = '${article.title} ${article.summary}'.toLowerCase();
  var score = 0;

  if (RegExp(r'\bartificial intelligence\b').hasMatch(text)) {
    score += 6;
  }
  if (RegExp(r'\bgenerative ai\b|\bgenai\b').hasMatch(text)) {
    score += 6;
  }
  if (RegExp(r'\bdeep[ -]?fake(s)?\b').hasMatch(text)) {
    score += 7;
  }
  if (RegExp(r'\bsynthetic media\b').hasMatch(text)) {
    score += 7;
  }
  if (RegExp(r'\bvoice clon(e|ed|ing)?\b|\bcloned voice\b').hasMatch(text)) {
    score += 7;
  }
  if (RegExp(r'\bai[- ]generated\b|\bai[- ]made\b|\bai[- ]created\b').hasMatch(text)) {
    score += 6;
  }
  if (RegExp(r'\bai[- ]powered\b|\bai[- ]driven\b|\bai[- ]assisted\b').hasMatch(text)) {
    score += 5;
  }
  if (RegExp(r'(^|[^a-z0-9])ai([^a-z0-9]|$)').hasMatch(text)) {
    score += 4;
  }
  if (RegExp(
    r'\bchatgpt\b|\bopenai\b|\bgemini\b|\bgoogle ai\b|\bclaude\b|\banthropic\b|\bcopilot\b|\bgrok\b|\bmeta ai\b|\bllm(s)?\b|\blarge language model(s)?\b',
  ).hasMatch(text)) {
    score += 4;
  }

  return score >= 4;
}

class _AwarenessRefreshResult {
  final String message;
  final String? warning;
  final int activeCount;
  final bool refreshed;

  const _AwarenessRefreshResult({
    required this.message,
    required this.activeCount,
    required this.refreshed,
    this.warning,
  });
}

class AwarenessFeedException implements Exception {
  final String message;
  const AwarenessFeedException(this.message);

  @override
  String toString() => message;
}

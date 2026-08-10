import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/content_item.dart';
import '../models/game_item.dart';
import '../models/lesson.dart';
import '../models/news_item.dart';
import '../models/quiz.dart';
import '../repositories/content_repository.dart';
import '../services/storage_service.dart';

class ContentController extends ChangeNotifier {
  final ContentRepository? _repository;
  final StorageService _storage;

  ContentController({ContentRepository? repository, StorageService? storage})
    : _repository = repository,
      _storage = storage ?? StorageService();

  static const _learnerCacheKey = 'publishedContentCacheV1';
  static const _adminCacheKey = 'adminContentCacheV1';

  StreamSubscription<List<ContentItem>>? _contentSubscription;
  Timer? _reconnectTimer;
  List<ContentItem> _items = const [];
  List<Module> _modules = const [];
  List<Quiz> _quizzes = const [];
  List<GameRound> _activities = const [];
  List<NewsItem> _awarenessItems = const [];
  bool _isLoading = false;
  bool _isMutating = false;
  bool _hasLoaded = false;
  bool _isLive = false;
  bool _isUsingSavedContent = false;
  String? _errorMessage;
  String? _boundUserId;
  bool _boundAsAdministrator = false;
  DateTime? _lastUpdatedAt;
  int _loadGeneration = 0;

  List<ContentItem> get items => List.unmodifiable(_items);
  List<Module> get modules => List.unmodifiable(_modules);
  List<Quiz> get quizzes => List.unmodifiable(_quizzes);
  List<GameRound> get activities => List.unmodifiable(_activities);
  List<NewsItem> get awarenessItems => List.unmodifiable(_awarenessItems);
  List<String> get lessonIds => _modules
      .expand((module) => module.lessons)
      .map((lesson) => lesson.id)
      .toList(growable: false);
  List<String> get quizIds =>
      _quizzes.map((quiz) => quiz.id).toList(growable: false);
  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  bool get hasLoaded => _hasLoaded;
  bool get isLive => _isLive;
  bool get isUsingSavedContent => _isUsingSavedContent;
  bool get isBackendConfigured => _repository != null;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  Future<void> bindAuthenticatedUser(
    String? userId, {
    required bool isAdministrator,
  }) async {
    if (_boundUserId == userId && _boundAsAdministrator == isAdministrator) {
      return;
    }

    _boundUserId = userId;
    _boundAsAdministrator = isAdministrator;
    _loadGeneration++;
    await _contentSubscription?.cancel();
    _contentSubscription = null;

    if (userId == null) {
      _errorMessage = null;
      _isLoading = false;
      _hasLoaded = false;
      _isLive = false;
      _isUsingSavedContent = false;
      _lastUpdatedAt = null;
      _reconnectTimer?.cancel();
      _applyItems(const []);
      notifyListeners();
      return;
    }

    await refresh();
  }

  Future<void> refresh() async {
    final repository = _repository;
    if (_boundUserId == null) return;

    if (!_hasLoaded) {
      final cached = await _readCache();
      if (cached.isNotEmpty) {
        _applyItems(cached);
        _hasLoaded = true;
        _isUsingSavedContent = true;
        notifyListeners();
      }
    }

    if (repository == null) {
      _isLoading = false;
      _hasLoaded = true;
      _isLive = false;
      _isUsingSavedContent = _items.isNotEmpty;
      _errorMessage = _items.isNotEmpty
          ? 'You are viewing saved learning content. Connect to the internet to check for updates.'
          : 'Learning content is unavailable right now.';
      notifyListeners();
      return;
    }

    final generation = ++_loadGeneration;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loaded = await repository.fetchItems(
        includeUnpublished: _boundAsAdministrator,
      );
      if (generation != _loadGeneration) return;
      _applyItems(loaded);
      _hasLoaded = true;
      _isLive = true;
      _isUsingSavedContent = false;
      _lastUpdatedAt = DateTime.now();
      _reconnectTimer?.cancel();
      await _saveCache(loaded);
      if (_contentSubscription == null) {
        _startLiveUpdates();
      }
    } catch (_) {
      if (generation != _loadGeneration) return;
      final cached = _items.isNotEmpty ? _items : await _readCache();
      if (cached.isNotEmpty) {
        _applyItems(cached);
        _hasLoaded = true;
        _isLive = false;
        _isUsingSavedContent = true;
        _errorMessage =
            'You appear to be offline. Showing saved learning content.';
      } else {
        _hasLoaded = true;
        _isLive = false;
        _isUsingSavedContent = false;
        _errorMessage =
            'Learning content could not be loaded. Check your connection and try again.';
      }
      _scheduleReconnect();
    } finally {
      if (generation == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _startLiveUpdates() {
    final repository = _repository;
    if (repository == null || _boundUserId == null) return;

    final previousSubscription = _contentSubscription;
    _contentSubscription = null;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _contentSubscription = repository.watchVisibleItems().listen(
      (loaded) {
        if (_boundUserId == null) return;
        _applyItems(loaded);
        _hasLoaded = true;
        _isLoading = false;
        _isLive = true;
        _isUsingSavedContent = false;
        _errorMessage = null;
        _lastUpdatedAt = DateTime.now();
        _reconnectTimer?.cancel();
        unawaited(_saveCache(loaded));
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_boundUserId == null) return;
        final failedSubscription = _contentSubscription;
        _contentSubscription = null;
        if (failedSubscription != null) {
          unawaited(failedSubscription.cancel());
        }
        _isLive = false;
        _isUsingSavedContent = _items.isNotEmpty;
        _errorMessage = _items.isNotEmpty
            ? 'Connection lost. You can keep using the saved learning content.'
            : 'Learning content is temporarily unavailable. Try again when you are back online.';
        _scheduleReconnect();
        notifyListeners();
      },
    );
  }

  Quiz? findQuizById(String quizId) {
    for (final quiz in _quizzes) {
      if (quiz.id == quizId) return quiz;
    }
    return null;
  }

  Future<bool> createItem(ContentItem item) async {
    return _mutate(() async {
      await _requireRepository().createItem(item);
      await refresh();
    });
  }

  Future<bool> updateItem(ContentItem item) async {
    return _mutate(() async {
      await _requireRepository().updateItem(item);
      await refresh();
    });
  }

  Future<bool> setStatus(ContentItem item, ContentStatus status) {
    return updateItem(
      item.copyWith(
        status: status,
        publicationDate:
            status == ContentStatus.published && item.publicationDate == null
            ? DateTime.now()
            : item.publicationDate,
      ),
    );
  }

  Future<bool> deleteItem(ContentItem item) async {
    return _mutate(() async {
      await _requireRepository().deleteItem(item.id);
      await refresh();
    });
  }

  Future<List<ContentVersion>> loadVersions(String contentId) async {
    return _requireRepository().fetchVersions(contentId);
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _mutate(Future<void> Function() operation) async {
    if (_isMutating || !_boundAsAdministrator) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
      return true;
    } catch (error) {
      _errorMessage = _friendlyMessage(error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  ContentRepository _requireRepository() {
    final repository = _repository;
    if (repository == null) {
      throw StateError(
        'Online content management is not available in this build.',
      );
    }
    return repository;
  }

  void _scheduleReconnect() {
    if (_boundUserId == null || _repository == null) return;
    if (_reconnectTimer?.isActive ?? false) return;
    _reconnectTimer = Timer(const Duration(seconds: 15), () {
      if (_boundUserId != null && !_isLive && !_isLoading) {
        unawaited(refresh());
      }
    });
  }

  String get _cacheKey =>
      _boundAsAdministrator ? _adminCacheKey : _learnerCacheKey;

  Future<void> _saveCache(List<ContentItem> items) async {
    try {
      await _storage.init();
      await _storage.setString(
        _cacheKey,
        jsonEncode(
          items.map((item) => item.toDatabaseMap()).toList(growable: false),
        ),
      );
    } catch (_) {
      // Saved content is optional and must never block fresh content.
    }
  }

  Future<List<ContentItem>> _readCache() async {
    try {
      await _storage.init();
      final raw = _storage.getString(_cacheKey);
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => ContentItem.fromMap(Map<String, dynamic>.from(value)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void _applyItems(List<ContentItem> source) {
    final sorted = List<ContentItem>.from(source)
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.title.compareTo(b.title);
      });
    _items = List.unmodifiable(sorted);

    final published = sorted
        .where((item) => item.status == ContentStatus.published)
        .toList(growable: false);

    _quizzes = published
        .where((item) => item.type == ContentType.quiz)
        .map(
          (item) => Quiz(
            id: item.id,
            title: item.title,
            description: item.description,
            question: item.question,
            options: item.options,
            correctIndex: item.correctIndex ?? 0,
            explanation: item.explanation,
          ),
        )
        .where((quiz) => quiz.isValid)
        .toList(growable: false);

    final lessonItems = published
        .where((item) => item.type == ContentType.lesson)
        .toList(growable: false);
    _modules = published
        .where((item) => item.type == ContentType.module)
        .map(
          (module) => Module(
            id: module.id,
            title: module.title,
            description: module.description,
            icon: module.icon.isEmpty ? 'ai' : module.icon,
            lessons: lessonItems
                .where((lesson) => lesson.parentId == module.id)
                .map(
                  (lesson) => Lesson(
                    id: lesson.id,
                    title: lesson.title,
                    content: lesson.body,
                    estimatedMinutes: lesson.estimatedMinutes,
                    quizId: lesson.quizId ?? '',
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    _activities = published
        .where((item) => item.type == ContentType.activity)
        .map(
          (item) => GameRound(
            id: item.id,
            title: item.title,
            imagePathA: item.imagePathA,
            imagePathB: item.imagePathB,
            isAAI: item.isAAI ?? false,
            explanation: item.explanation,
          ),
        )
        .where(
          (round) =>
              round.imagePathA.trim().isNotEmpty &&
              round.imagePathB.trim().isNotEmpty,
        )
        .toList(growable: false);

    _awarenessItems = published
        .where((item) => item.type == ContentType.awareness)
        .map(
          (item) => NewsItem(
            id: item.id,
            title: item.title,
            summary: item.description,
            date: _formatDate(item.publicationDate),
            sourceUrl: item.sourceUrl,
            reviewDate: item.reviewDate,
          ),
        )
        .toList(growable: false);
  }

  String _friendlyMessage(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('duplicate') || value.contains('already exists')) {
      return 'An item with the same information already exists.';
    }
    if (value.contains('permission') || value.contains('not authorized')) {
      return 'You do not have permission to make this change.';
    }
    return 'The change could not be completed. Check your connection and try again.';
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _contentSubscription?.cancel();
    super.dispose();
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Publication date not set';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

import 'package:flutter/foundation.dart';

import '../../data/models/image_comparison.dart';
import '../../data/services/verification_media_service.dart';

class ImageComparisonController extends ChangeNotifier {
  ImageComparisonController({VerificationMediaGateway? service})
    : _service = service;

  static const Duration _cacheTtl = Duration(minutes: 12);

  final VerificationMediaGateway? _service;

  String? _activeUserId;
  int _requestEpoch = 0;
  bool _disposed = false;

  bool _isLoading = false;
  String? _errorMessage;

  List<ImageComparisonRound> _rounds = const [];
  DateTime? _lastLoadedAt;
  Future<bool>? _roundLoadInFlight;

  final Set<String> _seenIds = <String>{};

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  List<ImageComparisonRound> get rounds => List.unmodifiable(_rounds);

  bool get hasCachedRounds {
    if (_rounds.length < 2 || _lastLoadedAt == null) {
      return false;
    }

    return DateTime.now().difference(_lastLoadedAt!) < _cacheTtl;
  }

  Future<void> bindAuthenticatedUser(String? userId) async {
    if (_disposed) return;
    if (_activeUserId == userId) {
      return;
    }

    _activeUserId = userId;
    _requestEpoch += 1;
    _roundLoadInFlight = null;

    _rounds = const [];
    _lastLoadedAt = null;

    _errorMessage = null;
    _isLoading = false;

    _seenIds.clear();

    notifyListeners();
  }

  /// Uses an already prepared set when it is still fresh.
  /// This makes reopening Compare Images almost instant.
  Future<bool> ensureRounds({int count = 5}) async {
    if (hasCachedRounds) {
      return true;
    }

    return _fetchRounds(count: count, replaceWithFresh: false);
  }

  /// Used when the learner explicitly asks for another set.
  Future<bool> loadFreshRounds({int count = 5}) async {
    return _fetchRounds(count: count, replaceWithFresh: true);
  }

  Future<ImageComparisonAttemptResult?> submitAttempt({
    required String roundId,
    required String selectedSide,
  }) async {
    final service = _service;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    if (service == null || userId == null) return null;
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      final result = await service.submitAttempt(
        roundId: roundId,
        selectedSide: selectedSide,
      );
      if (!_isCurrent(userId, epoch)) return null;
      return result;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Image comparison submission failed: $error\n$stackTrace');
      }
      if (_isCurrent(userId, epoch)) {
        _errorMessage =
            'Your answer could not be checked or saved. Please try again.';
        notifyListeners();
      }
      return null;
    }
  }

  Future<bool> _fetchRounds({
    required int count,
    required bool replaceWithFresh,
  }) {
    final inFlight = _roundLoadInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final request = _performFetchRounds(
      count: count,
      replaceWithFresh: replaceWithFresh,
    );
    _roundLoadInFlight = request;
    return request.whenComplete(() {
      if (identical(_roundLoadInFlight, request)) {
        _roundLoadInFlight = null;
      }
    });
  }

  Future<bool> _performFetchRounds({
    required int count,
    required bool replaceWithFresh,
  }) async {
    final service = _service;
    final userId = _activeUserId;
    final epoch = _requestEpoch;

    if (service == null || userId == null) {
      _errorMessage = 'Please sign in again to compare images.';
      notifyListeners();
      return false;
    }

    if (!replaceWithFresh && hasCachedRounds) {
      return true;
    }

    _isLoading = true;
    _errorMessage = null;

    notifyListeners();

    try {
      final result = await service.fetchRounds(count: count, seenIds: _seenIds);

      if (!_isCurrent(userId, epoch)) {
        return false;
      }

      _rounds = result;
      _lastLoadedAt = DateTime.now();

      for (final item in result) {
        _seenIds
          ..add(item.id)
          ..add(item.imageA.id)
          ..add(item.imageB.id);
      }

      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Image comparison loading failed: $error\n$stackTrace');
      }
      if (_isCurrent(userId, epoch)) {
        _errorMessage = error.toString();
      }

      return false;
    } finally {
      if (_isCurrent(userId, epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void clearError() {
    if (_disposed) return;
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  bool _isCurrent(String userId, int epoch) {
    return !_disposed && _activeUserId == userId && _requestEpoch == epoch;
  }

  @override
  void dispose() {
    _disposed = true;
    _requestEpoch += 1;
    _roundLoadInFlight = null;
    super.dispose();
  }
}

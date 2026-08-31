import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/app_profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/storage_service.dart';

class AuthController extends ChangeNotifier {
  static const _pendingSignupEmailKey = 'pendingSignupEmailV1';

  final AuthGateway? _repository;
  final StorageService _storage;

  AuthController({AuthGateway? repository, StorageService? storage})
    : _repository = repository,
      _storage = storage ?? StorageService();

  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _profileLoadFuture;
  String? _profileLoadUserId;
  Session? _session;
  AppProfile? _profile;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isProfileLoading = false;
  bool _isPasswordRecovery = false;
  bool _profileRoleAuthoritative = false;
  bool _isDisposed = false;
  bool _hasPendingSignupConfirmation = false;
  String? _pendingEmail;
  String? _errorMessage;
  List<AppProfile>? _allProfilesCache;
  DateTime? _allProfilesCacheAt;

  bool get isBackendConfigured => _repository != null;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isProfileLoading => _isProfileLoading;
  bool get isAuthenticated => _session?.user != null;
  bool get isEmailVerified => _session?.user.emailConfirmedAt != null;
  bool get isAdministrator =>
      _profileRoleAuthoritative &&
      _profile?.role == AppRole.administrator &&
      _profile?.id == userId;
  bool get isLearner => isAuthenticated && !isAdministrator;
  bool get isPasswordRecovery => _isPasswordRecovery;
  bool get isReadyForRouting =>
      isInitialized &&
      (!isAuthenticated ||
          !isEmailVerified ||
          (!_isProfileLoading && _profile != null));
  String? get errorMessage => _errorMessage;
  String? get pendingEmail => _pendingEmail;
  bool get hasPendingSignupVerification =>
      _hasPendingSignupConfirmation &&
      (_pendingEmail?.isNotEmpty ?? false);
  Session? get session => _session;
  User? get user => _session?.user;
  AppProfile? get profile => _profile;
  String? get userId => user?.id;
  String get email => _profile?.email ?? user?.email ?? _pendingEmail ?? '';

  String get displayName {
    final name = _profile?.fullName.trim() ?? '';
    if (name.isNotEmpty) return name;
    final metadataName = user?.userMetadata?['full_name']?.toString().trim();
    if (metadataName != null && metadataName.isNotEmpty) return metadataName;
    final currentEmail = email;
    return currentEmail.isEmpty
        ? 'PromptWise learner'
        : currentEmail.split('@').first;
  }

  Future<void> init() async {
    if (_isInitialized) return;

    final repository = _repository;
    if (repository == null) {
      _isInitialized = true;
      _notifyListeners();
      return;
    }

    await _restorePendingSignupEmail();
    _session = repository.currentSession;
    final restoredUser = _session?.user;
    if (restoredUser != null) {
      _pendingEmail = restoredUser.email ?? _pendingEmail;
      if (restoredUser.emailConfirmedAt != null) {
        _hasPendingSignupConfirmation = false;
        await _clearPendingSignupEmail();
      } else {
        _hasPendingSignupConfirmation = true;
        await _persistPendingSignupEmail(
          restoredUser.email ?? _pendingEmail ?? '',
        );
      }
    }

    // Subscribe before profile hydration so auth changes are never missed while
    // a returning device is restoring its local account state.
    _authSubscription = repository.authStateChanges.listen(
      handleAuthState,
      onError: (Object error, StackTrace stackTrace) {
        _errorMessage = _friendlyMessage(error);
        _notifyListeners();
      },
    );

    if (_session?.user != null) {
      // _loadProfileOnce is cache-first. Returning users can route from the
      // saved profile immediately while the fresh Supabase copy updates in the
      // background. First-time users still wait for the authoritative profile.
      await _loadProfileOnce(_session!.user.id);
    }

    _isInitialized = true;
    _notifyListeners();
  }

  @visibleForTesting
  void handleAuthState(AuthState state) {
    final previousUserId = _session?.user.id;
    final nextUserId = state.session?.user.id;
    _session = state.session;

    if (state.event == AuthChangeEvent.passwordRecovery) {
      _isPasswordRecovery = true;
    }

    if (state.event == AuthChangeEvent.signedOut || state.session == null) {
      _profile = null;
      _profileRoleAuthoritative = false;
      _isProfileLoading = false;
      _profileLoadFuture = null;
      _profileLoadUserId = null;
      _allProfilesCache = null;
      _allProfilesCacheAt = null;
      if (state.event == AuthChangeEvent.signedOut) {
        _isPasswordRecovery = false;
        _hasPendingSignupConfirmation = false;
        unawaited(_clearPendingSignupEmail());
      }
      _notifyListeners();
      return;
    }

    if (previousUserId != nextUserId) {
      _profile = null;
      _profileRoleAuthoritative = false;
    }

    _pendingEmail = state.session?.user.email ?? _pendingEmail;
    if (state.session?.user.emailConfirmedAt != null) {
      _hasPendingSignupConfirmation = false;
      unawaited(_clearPendingSignupEmail());
    } else {
      _hasPendingSignupConfirmation = true;
      final email = state.session?.user.email;
      if (email != null) unawaited(_persistPendingSignupEmail(email));
    }
    _notifyListeners();

    if (nextUserId != null && _profile?.id != nextUserId) {
      unawaited(_loadProfileOnce(nextUserId));
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    _pendingEmail = email.trim();
    _hasPendingSignupConfirmation = true;
    return _run(() async {
      final response = await repository.signUp(
        fullName: fullName,
        email: email,
        password: password,
      );
      if (_isDisposed) return;
      if (response.user == null) {
        throw const AuthException('The signup request returned no account.');
      }
      _pendingEmail = email.trim();
      _session = response.session;
      if (response.session?.user.emailConfirmedAt != null) {
        _hasPendingSignupConfirmation = false;
        await _clearPendingSignupEmail();
        await _loadProfileOnce(response.session!.user.id);
      } else {
        _hasPendingSignupConfirmation = true;
        await _persistPendingSignupEmail(_pendingEmail!);
      }
    });
  }

  Future<bool> signIn({required String email, required String password}) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    _pendingEmail = email.trim();
    return _run(() async {
      final response = await repository.signIn(
        email: email,
        password: password,
      );
      if (_isDisposed) return;
      _pendingEmail = email.trim();
      _session = response.session;
      final signedInUser = response.user;
      if (signedInUser == null || response.session == null) {
        throw AuthException('No active session was created.');
      }
      _hasPendingSignupConfirmation = false;
      await _clearPendingSignupEmail();
      await _loadProfileOnce(signedInUser.id);
    });
  }

  Future<bool> sendSignInOtp(String email) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final targetEmail = email.trim();
    if (targetEmail.isEmpty) {
      _errorMessage = 'Enter your registered email address.';
      _notifyListeners();
      return false;
    }

    _pendingEmail = targetEmail;
    return _run(() async {
      await repository.sendSignInOtp(targetEmail);
    });
  }

  Future<bool> verifySignInOtp({
    required String email,
    required String token,
  }) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final normalizedEmail = email.trim();
    final normalizedToken = token.replaceAll(RegExp(r'\s+'), '');
    if (normalizedEmail.isEmpty) {
      _errorMessage = 'Enter the email address that received the code.';
      _notifyListeners();
      return false;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedToken)) {
      _errorMessage = 'Enter the complete 6-digit code.';
      _notifyListeners();
      return false;
    }

    _pendingEmail = normalizedEmail;
    return _run(() async {
      final response = await repository.verifyEmailOtp(
        email: normalizedEmail,
        token: normalizedToken,
      );
      if (_isDisposed) return;
      _session = response.session;

      if (response.user == null || response.session == null) {
        throw AuthException('The code could not create an active session.');
      }

      _hasPendingSignupConfirmation = false;
      await _clearPendingSignupEmail();
      await _loadProfileOnce(response.user!.id);
    });
  }

  Future<bool> resendSignupConfirmation({String? email}) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final targetEmail = (email ?? _pendingEmail ?? user?.email ?? '').trim();
    if (targetEmail.isEmpty) {
      _errorMessage = 'Enter the email address used to create the account.';
      _notifyListeners();
      return false;
    }

    _pendingEmail = targetEmail;
    _hasPendingSignupConfirmation = true;
    return _run(() async {
      await repository.resendSignupConfirmation(targetEmail);
      if (_isDisposed) return;
      await _persistPendingSignupEmail(targetEmail);
    });
  }

  Future<bool> resendVerification({String? email}) async {
    return resendSignupConfirmation(email: email);
  }

  Future<void> clearPendingSignupConfirmation() async {
    _hasPendingSignupConfirmation = false;
    _errorMessage = null;
    await _clearPendingSignupEmail();
    _notifyListeners();
  }

  Future<bool> sendPasswordReset(String email) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final targetEmail = email.trim();
    _pendingEmail = targetEmail;
    return _run(() async {
      await repository.sendPasswordReset(targetEmail);
    });
  }

  Future<bool> updatePassword(String password) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    return _run(() async {
      await repository.updatePassword(password);
    });
  }

  Future<bool> updateFullName(String fullName) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    return _run(() async {
      _profile = await repository.updateMyFullName(fullName);
      _profileRoleAuthoritative = true;
      final profile = _profile;
      if (profile != null) await _saveProfileCache(profile);
    });
  }

  Future<List<AppProfile>> loadAllProfiles({bool force = false}) async {
    final repository = _repository;
    if (repository == null || !isAdministrator) return const [];
    final cached = _allProfilesCache;
    final cachedAt = _allProfilesCacheAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 5)) {
      return cached;
    }
    final loaded = await repository.fetchAllProfiles();
    _allProfilesCache = List<AppProfile>.unmodifiable(loaded);
    _allProfilesCacheAt = DateTime.now();
    return _allProfilesCache!;
  }

  Future<void> refreshProfile() async {
    final id = userId;
    if (id == null) return;
    _profile = null;
    _profileRoleAuthoritative = false;
    await _loadProfileOnce(id);
  }

  Future<bool> signOut() async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    return _run(() async {
      await repository.signOut();
      _session = null;
      _profile = null;
      _profileRoleAuthoritative = false;
      _isProfileLoading = false;
      _profileLoadFuture = null;
      _profileLoadUserId = null;
      _allProfilesCache = null;
      _allProfilesCacheAt = null;
      _isPasswordRecovery = false;
      _hasPendingSignupConfirmation = false;
      await _clearPendingSignupEmail();
    });
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notifyListeners();
  }

  void completePasswordRecovery() {
    if (!_isPasswordRecovery) return;
    _isPasswordRecovery = false;
    _errorMessage = null;
    _notifyListeners();
  }

  Future<void> _loadProfileOnce(String userId) {
    if (_profile?.id == userId) return Future<void>.value();

    final activeLoad = _profileLoadFuture;
    if (_profileLoadUserId == userId && activeLoad != null) {
      return activeLoad;
    }

    _profileLoadUserId = userId;
    _isProfileLoading = true;
    _notifyListeners();

    final future = _loadProfileCacheFirst(userId);
    _profileLoadFuture = future;

    return future.whenComplete(() {
      if (_profileLoadUserId != userId) return;
      _profileLoadFuture = null;
      _profileLoadUserId = null;
      if (_session?.user.id == userId) {
        _isProfileLoading = false;
        _notifyListeners();
      }
    });
  }

  Future<void> _loadProfileCacheFirst(String userId) async {
    final repository = _repository;
    if (repository == null) return;

    final cached = await _readProfileCache(userId);
    if (_session?.user.id != userId) return;

    if (cached != null) {
      // Cached identity fields improve startup, but a cached role must never
      // grant administrator access after the server role has been revoked.
      _profile = AppProfile(
        id: cached.id,
        email: cached.email,
        fullName: cached.fullName,
        role: AppRole.learner,
        createdAt: cached.createdAt,
        updatedAt: cached.updatedAt,
      );
      _profileRoleAuthoritative = false;
      _isProfileLoading = false;
      _notifyListeners();

      // Do not make a returning learner stare at a loading screen while a
      // network round trip refreshes information that is already safe to show.
      unawaited(_refreshProfileFromNetwork(userId));
      return;
    }

    await _loadProfileFromNetwork(userId, showOfflineMessage: true);
  }

  Future<void> _refreshProfileFromNetwork(String userId) async {
    await _loadProfileFromNetwork(userId, showOfflineMessage: false);
  }

  Future<void> _loadProfileFromNetwork(
    String userId, {
    required bool showOfflineMessage,
  }) async {
    final repository = _repository;
    if (repository == null) return;

    try {
      final loaded = await repository.fetchMyProfile(userId);
      if (_session?.user.id != userId) return;
      _profile = loaded ?? _fallbackProfile(userId);
      _profileRoleAuthoritative = loaded != null;
      await _saveProfileCache(_profile!);
      _notifyListeners();
    } catch (error, stackTrace) {
      _debugFailure('Profile refresh', error, stackTrace);
      if (_session?.user.id != userId) return;

      final cached = _profile?.id == userId
          ? _profile
          : await _readProfileCache(userId);
      _profile = cached ?? _fallbackProfile(userId);
      _profileRoleAuthoritative = false;

      if (showOfflineMessage) {
        _errorMessage = _isConnectionFailure(error)
            ? 'You appear to be offline. Using saved account information until the connection returns.'
            : 'Account information could not be refreshed. Saved learner access is being used; administrator access requires a successful server check.';
      }
      _notifyListeners();
    }
  }

  String _profileCacheKey(String userId) => 'profileCacheV1_$userId';

  Future<void> _saveProfileCache(AppProfile profile) async {
    try {
      await _storage.init();
      await _storage.setString(
        _profileCacheKey(profile.id),
        jsonEncode({
          'id': profile.id,
          'email': profile.email,
          'full_name': profile.fullName,
          'role': profile.role.databaseValue,
          'created_at': profile.createdAt?.toIso8601String(),
          'updated_at': profile.updatedAt?.toIso8601String(),
        }),
      );
    } catch (error, stackTrace) {
      _debugFailure('Profile cache write', error, stackTrace);
      // Account caching is optional and must not block sign-in.
    }
  }

  Future<AppProfile?> _readProfileCache(String userId) async {
    try {
      await _storage.init();
      final raw = _storage.getString(_profileCacheKey(userId));
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = AppProfile.fromMap(Map<String, dynamic>.from(decoded));
      return profile.id == userId ? profile : null;
    } catch (error, stackTrace) {
      _debugFailure('Profile cache read', error, stackTrace);
      return null;
    }
  }

  AppProfile _fallbackProfile(String userId) {
    return AppProfile(
      id: userId,
      email: user?.email ?? _pendingEmail ?? '',
      fullName: user?.userMetadata?['full_name']?.toString() ?? '',
      role: AppRole.learner,
    );
  }

  Future<bool> _run(Future<void> Function() operation) async {
    if (_isLoading || _isDisposed) return false;
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();

    try {
      await operation();
      if (_isDisposed) return false;
      return true;
    } catch (error, stackTrace) {
      _debugFailure('Authentication request', error, stackTrace);
      if (_isDisposed) return false;
      _errorMessage = _friendlyMessage(error);
      return false;
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  bool _configurationError() {
    _errorMessage = 'Sign in is not available in this build.';
    _notifyListeners();
    return false;
  }

  bool _isConnectionFailure(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('failed to fetch') ||
        value.contains('timeout');
  }

  void _debugFailure(String label, Object error, StackTrace stackTrace) {
    if (kDebugMode) debugPrint('$label failed: $error\n$stackTrace');
  }

  String _friendlyMessage(Object error) {
    if (_isConnectionFailure(error)) {
      return 'The verification service could not be reached. Check your connection and try again.';
    }
    if (error is AuthException) {
      final message = error.message.trim();
      final lower = message.toLowerCase();
      final code = error.code?.toLowerCase();
      if (lower.contains('invalid login credentials')) {
        return 'The email or password is incorrect.';
      }
      if (lower.contains('email not confirmed')) {
        return 'Verify your email using the confirmation link we sent before signing in.';
      }
      if (lower.contains('already confirmed') ||
          lower.contains('already been confirmed')) {
        return 'This email is already verified. Sign in to continue.';
      }
      if (lower.contains('user already registered')) {
        return 'An account already exists for this email.';
      }
      if (lower.contains('email address not authorized')) {
        return 'Email delivery is not available for this address right now. Please try again later.';
      }
      if (code == 'over_email_send_rate_limit' ||
          code == 'over_request_rate_limit' ||
          lower.contains('rate limit') ||
          lower.contains('too many requests')) {
        return 'Too many email requests were sent. Please wait a while before trying again.';
      }
      if (code == 'otp_expired' ||
          lower.contains('token has expired') ||
          lower.contains('otp_expired') ||
          lower.contains('already used')) {
        return 'This verification code has expired or was already used. Request a new code and use only the latest email.';
      }
      if (lower.contains('invalid token') ||
          lower.contains('invalid otp') ||
          lower.contains('token is invalid') ||
          lower.contains('code is invalid')) {
        return 'That verification code is incorrect. Check the 6 digits and try again.';
      }
      if (lower.contains('user not found') ||
          lower.contains('signups not allowed')) {
        return 'No active PromptWise account was found for this email.';
      }
      if (lower.contains('password')) return message;
      return 'The account request could not be completed. Please try again.';
    }
    if (error is PostgrestException) {
      return 'The account change could not be saved. Please try again.';
    }
    if (error is FormatException) {
      return 'Some account information is invalid. Please check it and try again.';
    }
    return 'The request could not be completed. Check your connection and try again.';
  }

  Future<void> _restorePendingSignupEmail() async {
    try {
      await _storage.init();
      final email = _storage.getString(_pendingSignupEmailKey).trim();
      if (email.isEmpty) return;
      _pendingEmail = email;
      _hasPendingSignupConfirmation = true;
    } catch (error, stackTrace) {
      _debugFailure('Pending signup restore', error, stackTrace);
    }
  }

  Future<void> _persistPendingSignupEmail(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return;
    _pendingEmail = normalizedEmail;
    _hasPendingSignupConfirmation = true;
    try {
      await _storage.setString(_pendingSignupEmailKey, normalizedEmail);
    } catch (error, stackTrace) {
      _debugFailure('Pending signup save', error, stackTrace);
    }
  }

  Future<void> _clearPendingSignupEmail() async {
    try {
      await _storage.remove(_pendingSignupEmailKey);
    } catch (error, stackTrace) {
      _debugFailure('Pending signup clear', error, stackTrace);
    }
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }
}

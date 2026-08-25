import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/app_profile.dart';
import '../../data/models/auth_otp_request.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/storage_service.dart';

class AuthController extends ChangeNotifier {
  final AuthRepository? _repository;
  final StorageService _storage;

  AuthController({AuthRepository? repository, StorageService? storage})
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
  String? _pendingEmail;
  AuthOtpPurpose? _pendingOtpPurpose;
  String? _errorMessage;
  List<AppProfile>? _allProfilesCache;
  DateTime? _allProfilesCacheAt;

  bool get isBackendConfigured => _repository != null;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isProfileLoading => _isProfileLoading;
  bool get isAuthenticated => _session?.user != null;
  bool get isEmailVerified => _session?.user.emailConfirmedAt != null;
  bool get isAdministrator => _profile?.role == AppRole.administrator;
  bool get isLearner => _profile?.role == AppRole.learner;
  bool get isPasswordRecovery => _isPasswordRecovery;
  bool get isReadyForRouting =>
      isInitialized &&
      (!isAuthenticated ||
          !isEmailVerified ||
          (!_isProfileLoading && _profile != null));
  String? get errorMessage => _errorMessage;
  String? get pendingEmail => _pendingEmail;
  AuthOtpPurpose? get pendingOtpPurpose => _pendingOtpPurpose;
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
      notifyListeners();
      return;
    }

    _session = repository.currentSession;
    _pendingEmail = _session?.user.email;

    // Subscribe before profile hydration so auth changes are never missed while
    // a returning device is restoring its local account state.
    _authSubscription = repository.authStateChanges.listen(
      _handleAuthState,
      onError: (Object error, StackTrace stackTrace) {
        _errorMessage = _friendlyMessage(error);
        notifyListeners();
      },
    );

    if (_session?.user != null) {
      // _loadProfileOnce is cache-first. Returning users can route from the
      // saved profile immediately while the fresh Supabase copy updates in the
      // background. First-time users still wait for the authoritative profile.
      await _loadProfileOnce(_session!.user.id);
    }

    _isInitialized = true;
    notifyListeners();
  }

  void _handleAuthState(AuthState state) {
    final previousUserId = _session?.user.id;
    final nextUserId = state.session?.user.id;
    _session = state.session;

    if (state.event == AuthChangeEvent.passwordRecovery) {
      _isPasswordRecovery = true;
      _pendingOtpPurpose = AuthOtpPurpose.recovery;
    }

    if (state.event == AuthChangeEvent.signedOut || state.session == null) {
      _profile = null;
      _isProfileLoading = false;
      _profileLoadFuture = null;
      _profileLoadUserId = null;
      _allProfilesCache = null;
      _allProfilesCacheAt = null;
      if (state.event == AuthChangeEvent.signedOut) {
        _isPasswordRecovery = false;
        _pendingOtpPurpose = null;
      }
      notifyListeners();
      return;
    }

    if (previousUserId != nextUserId) {
      _profile = null;
    }

    _pendingEmail = state.session?.user.email ?? _pendingEmail;
    notifyListeners();

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
    _pendingOtpPurpose = AuthOtpPurpose.signup;
    return _run(() async {
      final response = await repository.signUp(
        fullName: fullName,
        email: email,
        password: password,
      );
      _pendingEmail = email.trim();
      _session = response.session;
      if (response.session?.user != null) {
        await _loadProfileOnce(response.session!.user.id);
        _pendingOtpPurpose = null;
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
      _pendingEmail = email.trim();
      _session = response.session;
      final signedInUser = response.user;
      if (signedInUser == null || response.session == null) {
        throw AuthException('No active session was created.');
      }
      _pendingOtpPurpose = null;
      await _loadProfileOnce(signedInUser.id);
    });
  }

  Future<bool> sendSignInOtp(String email) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final targetEmail = email.trim();
    if (targetEmail.isEmpty) {
      _errorMessage = 'Enter your registered email address.';
      notifyListeners();
      return false;
    }

    _pendingEmail = targetEmail;
    _pendingOtpPurpose = AuthOtpPurpose.signIn;
    return _run(() async {
      await repository.sendSignInOtp(targetEmail);
    });
  }

  Future<bool> verifyOtp({
    required String email,
    required String token,
    required AuthOtpPurpose purpose,
  }) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final normalizedEmail = email.trim();
    final normalizedToken = token.replaceAll(RegExp(r'\s+'), '');
    if (normalizedToken.length != 6) {
      _errorMessage = 'Enter the complete 6-digit code.';
      notifyListeners();
      return false;
    }

    _pendingEmail = normalizedEmail;
    _pendingOtpPurpose = purpose;
    return _run(() async {
      final response = await repository.verifyEmailOtp(
        email: normalizedEmail,
        token: normalizedToken,
        purpose: purpose,
      );
      _session = response.session;

      if (response.user == null || response.session == null) {
        throw AuthException('The code could not create an active session.');
      }

      if (purpose == AuthOtpPurpose.recovery) {
        _isPasswordRecovery = true;
      } else {
        _pendingOtpPurpose = null;
        await _loadProfileOnce(response.user!.id);
      }
    });
  }

  Future<bool> resendOtp({
    required String email,
    required AuthOtpPurpose purpose,
  }) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final targetEmail = email.trim();
    if (targetEmail.isEmpty) {
      _errorMessage = 'Enter the email address used for the request.';
      notifyListeners();
      return false;
    }

    _pendingEmail = targetEmail;
    _pendingOtpPurpose = purpose;
    return _run(() async {
      switch (purpose) {
        case AuthOtpPurpose.signup:
          await repository.resendSignupConfirmation(targetEmail);
          break;
        case AuthOtpPurpose.signIn:
          await repository.sendSignInOtp(targetEmail);
          break;
        case AuthOtpPurpose.recovery:
          await repository.sendPasswordReset(targetEmail);
          break;
      }
    });
  }

  Future<bool> resendVerification({String? email}) async {
    final targetEmail = (email ?? _pendingEmail ?? user?.email ?? '').trim();
    return resendOtp(email: targetEmail, purpose: AuthOtpPurpose.signup);
  }

  Future<bool> sendPasswordReset(String email) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    final targetEmail = email.trim();
    _pendingEmail = targetEmail;
    _pendingOtpPurpose = AuthOtpPurpose.recovery;
    return _run(() async {
      await repository.sendPasswordReset(targetEmail);
    });
  }

  Future<bool> updatePassword(String password) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    return _run(() async {
      await repository.updatePassword(password);
      _isPasswordRecovery = false;
      _pendingOtpPurpose = null;
    });
  }

  Future<bool> updateFullName(String fullName) async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    return _run(() async {
      _profile = await repository.updateMyFullName(fullName);
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
    await _loadProfileOnce(id);
  }

  Future<bool> signOut() async {
    final repository = _repository;
    if (repository == null) return _configurationError();

    return _run(() async {
      await repository.signOut();
      _session = null;
      _profile = null;
      _isProfileLoading = false;
      _profileLoadFuture = null;
      _profileLoadUserId = null;
      _allProfilesCache = null;
      _allProfilesCacheAt = null;
      _isPasswordRecovery = false;
      _pendingOtpPurpose = null;
    });
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  void cancelPasswordRecovery() {
    if (!_isPasswordRecovery) return;
    _isPasswordRecovery = false;
    _pendingOtpPurpose = null;
    notifyListeners();
  }

  Future<void> _loadProfileOnce(String userId) {
    if (_profile?.id == userId) return Future<void>.value();

    final activeLoad = _profileLoadFuture;
    if (_profileLoadUserId == userId && activeLoad != null) {
      return activeLoad;
    }

    _profileLoadUserId = userId;
    _isProfileLoading = true;
    notifyListeners();

    final future = _loadProfileCacheFirst(userId);
    _profileLoadFuture = future;

    return future.whenComplete(() {
      if (_profileLoadUserId != userId) return;
      _profileLoadFuture = null;
      _profileLoadUserId = null;
      if (_session?.user.id == userId) {
        _isProfileLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> _loadProfileCacheFirst(String userId) async {
    final repository = _repository;
    if (repository == null) return;

    final cached = await _readProfileCache(userId);
    if (_session?.user.id != userId) return;

    if (cached != null) {
      _profile = cached;
      _isProfileLoading = false;
      notifyListeners();

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
      await _saveProfileCache(_profile!);
      notifyListeners();
    } catch (_) {
      if (_session?.user.id != userId) return;

      final cached = _profile?.id == userId
          ? _profile
          : await _readProfileCache(userId);
      _profile = cached ?? _fallbackProfile(userId);

      if (showOfflineMessage) {
        _errorMessage =
            'You appear to be offline. Using saved account information until the connection returns.';
      }
      notifyListeners();
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
    } catch (_) {
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
    } catch (_) {
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
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await operation();
      return true;
    } catch (error) {
      _errorMessage = _friendlyMessage(error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _configurationError() {
    _errorMessage = 'Sign in is not available in this build.';
    notifyListeners();
    return false;
  }

  String _friendlyMessage(Object error) {
    if (error is AuthException) {
      final message = error.message.trim();
      final lower = message.toLowerCase();
      if (lower.contains('invalid login credentials')) {
        return 'The email or password is incorrect.';
      }
      if (lower.contains('email not confirmed')) {
        return 'Confirm your email before signing in.';
      }
      if (lower.contains('user already registered')) {
        return 'An account already exists for this email.';
      }
      if (lower.contains('email address not authorized')) {
        return 'Email delivery is not available for this address right now. Please try again later.';
      }
      if (lower.contains('rate limit') || lower.contains('too many requests')) {
        return 'Too many email requests were sent. Please wait a while before requesting another code.';
      }
      if (lower.contains('token has expired') ||
          lower.contains('otp_expired') ||
          lower.contains('invalid token')) {
        return 'The code is invalid or expired. Request a new 6-digit code and use only the latest email.';
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

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../models/app_profile.dart';

abstract interface class AuthGateway {
  Session? get currentSession;
  Stream<AuthState> get authStateChanges;

  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  });
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  });
  Future<void> sendSignInOtp(String email);
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  });
  Future<void> signOut();
  Future<void> resendSignupConfirmation(String email);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<AppProfile?> fetchMyProfile(String userId);
  Future<AppProfile> updateMyFullName(String fullName);
  Future<List<AppProfile>> fetchAllProfiles();
}

class AuthRepository implements AuthGateway {
  final SupabaseClient client;

  const AuthRepository(this.client);

  @override
  Session? get currentSession => client.auth.currentSession;
  User? get currentUser => client.auth.currentUser;
  @override
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  }) {
    return client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: AppEnvironment.emailConfirmationRedirectUrl,
      data: {'full_name': fullName.trim()},
    );
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> sendSignInOtp(String email) {
    return client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: AppEnvironment.emailConfirmationRedirectUrl,
      shouldCreateUser: false,
    );
  }

  @override
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  @override
  Future<void> resendSignupConfirmation(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: AppEnvironment.emailConfirmationRedirectUrl,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AppEnvironment.passwordRecoveryRedirectUrl,
    );
  }

  @override
  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<AppProfile?> fetchMyProfile(String userId) async {
    final data = await client
        .from('profiles')
        .select('id, email, full_name, role, created_at, updated_at')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return AppProfile.fromMap(data);
  }

  @override
  Future<AppProfile> updateMyFullName(String fullName) async {
    final data = await client.rpc(
      'update_my_profile',
      params: {'p_full_name': fullName.trim()},
    );

    if (data is Map<String, dynamic>) {
      return AppProfile.fromMap(data);
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return AppProfile.fromMap(Map<String, dynamic>.from(data.first as Map));
    }
    throw const FormatException('Profile update returned no profile data.');
  }

  @override
  Future<List<AppProfile>> fetchAllProfiles() async {
    final data = await client
        .from('profiles')
        .select('id, email, full_name, role, created_at, updated_at')
        .order('created_at', ascending: false)
        .limit(500);

    return data
        .map<AppProfile>(
          (row) => AppProfile.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }
}

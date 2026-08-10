import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_environment.dart';
import '../models/app_profile.dart';
import '../models/auth_otp_request.dart';

class AuthRepository {
  final SupabaseClient client;

  const AuthRepository(this.client);

  Session? get currentSession => client.auth.currentSession;
  User? get currentUser => client.auth.currentUser;
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

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

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendSignInOtp(String email) {
    return client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: AppEnvironment.emailConfirmationRedirectUrl,
      shouldCreateUser: false,
    );
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
    required AuthOtpPurpose purpose,
  }) {
    final type = switch (purpose) {
      AuthOtpPurpose.signup => OtpType.email,
      AuthOtpPurpose.signIn => OtpType.email,
      AuthOtpPurpose.recovery => OtpType.recovery,
    };

    return client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: type,
    );
  }

  Future<void> signOut() => client.auth.signOut();

  Future<void> resendSignupConfirmation(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: AppEnvironment.emailConfirmationRedirectUrl,
    );
  }

  Future<void> sendPasswordReset(String email) {
    return client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AppEnvironment.passwordRecoveryRedirectUrl,
    );
  }

  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  Future<AppProfile?> fetchMyProfile(String userId) async {
    final data = await client
        .from('profiles')
        .select('id, email, full_name, role, created_at, updated_at')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return AppProfile.fromMap(data);
  }

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

  Future<List<AppProfile>> fetchAllProfiles() async {
    final data = await client
        .from('profiles')
        .select('id, email, full_name, role, created_at, updated_at')
        .order('created_at', ascending: false);

    return data
        .map<AppProfile>(
          (row) => AppProfile.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }
}

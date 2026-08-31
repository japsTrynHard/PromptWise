import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:promptwise/core/config/app_environment.dart';
import 'package:promptwise/core/routes/app_routes.dart';
import 'package:promptwise/data/models/app_profile.dart';
import 'package:promptwise/data/repositories/auth_repository.dart';
import 'package:promptwise/presentation/controllers/auth_controller.dart';
import 'package:promptwise/presentation/screens/auth/auth_gate_screen.dart';
import 'package:promptwise/presentation/screens/auth/login_screen.dart';
import 'package:promptwise/presentation/screens/auth/signup_confirmation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('signup creates and persists a pending confirmation-link account', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    final success = await harness.auth.register(
      fullName: 'Prompt Wise',
      email: ' learner@example.com ',
      password: 'password-123',
    );

    expect(success, isTrue);
    expect(harness.gateway.signupEmail, 'learner@example.com');
    expect(harness.auth.isAuthenticated, isFalse);
    expect(harness.auth.pendingEmail, 'learner@example.com');
    expect(harness.auth.hasPendingSignupVerification, isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('pendingSignupEmailV1'),
      'learner@example.com',
    );
  });

  testWidgets('signup confirmation screen contains links-only wording', (
    tester,
  ) async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _screenApp(
        harness.auth,
        const SignupConfirmationScreen(email: 'learner@example.com'),
      ),
    );

    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text('We sent a confirmation link to your email address.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Open the email and tap the confirmation link to verify your PromptWise account.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirmation email sent to learner@example.com'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('OTP'), findsNothing);
    expect(find.textContaining('6-digit'), findsNothing);
    expect(find.textContaining('verification code'), findsNothing);
  });

  testWidgets('pending email survives restart and restores one confirmation screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'pendingSignupEmailV1': 'returning@example.com',
    });
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_screenApp(harness.auth, const AuthGateScreen()));

    expect(harness.auth.hasPendingSignupVerification, isTrue);
    expect(find.byType(SignupConfirmationScreen), findsOneWidget);
    expect(find.text('Confirmation email sent to returning@example.com'), findsOneWidget);
  });

  testWidgets('unconfirmed password sign-in offers confirmation-email resend', (
    tester,
  ) async {
    final harness = await _createHarness(
      signInError: const AuthException(
        'Email not confirmed',
        code: 'email_not_confirmed',
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_screenApp(harness.auth, const LoginScreen()));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'learner@example.com');
    await tester.enterText(fields.at(1), 'password-123');
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Resend confirmation email'), findsOneWidget);
    expect(find.textContaining('confirmation link'), findsOneWidget);
  });

  test('resend requests another Supabase signup confirmation email', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    final success = await harness.auth.resendSignupConfirmation(
      email: ' learner@example.com ',
    );

    expect(success, isTrue);
    expect(harness.gateway.resentSignupEmails, ['learner@example.com']);
    expect(harness.auth.hasPendingSignupVerification, isTrue);
  });

  test('resend rate limit has a specific wait message', () async {
    final harness = await _createHarness(
      resendError: const AuthException(
        'Email rate limit exceeded',
        code: 'over_email_send_rate_limit',
      ),
    );
    addTearDown(harness.dispose);

    final success = await harness.auth.resendSignupConfirmation(
      email: 'learner@example.com',
    );

    expect(success, isFalse);
    expect(
      harness.auth.errorMessage,
      'Too many email requests were sent. Please wait a while before trying again.',
    );
  });

  test('already-confirmed account is directed to sign in', () async {
    final harness = await _createHarness(
      resendError: const AuthException('Email already confirmed'),
    );
    addTearDown(harness.dispose);

    final success = await harness.auth.resendSignupConfirmation(
      email: 'learner@example.com',
    );

    expect(success, isFalse);
    expect(
      harness.auth.errorMessage,
      'This email is already verified. Sign in to continue.',
    );
  });

  test('network failure remains distinct from confirmation-link errors', () async {
    final harness = await _createHarness(
      resendError: Exception('SocketException: network unreachable'),
    );
    addTearDown(harness.dispose);

    final success = await harness.auth.resendSignupConfirmation(
      email: 'learner@example.com',
    );

    expect(success, isFalse);
    expect(
      harness.auth.errorMessage,
      'The verification service could not be reached. Check your connection and try again.',
    );
  });

  testWidgets('confirmation resend remains disabled until cooldown ends', (
    tester,
  ) async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _screenApp(
        harness.auth,
        const SignupConfirmationScreen(email: 'learner@example.com'),
      ),
    );

    expect(find.text('Resend available in 60s'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Resend confirmation email'), findsOneWidget);
    await tester.tap(find.text('Resend confirmation email'));
    await tester.pump();

    expect(harness.gateway.resentSignupEmails, ['learner@example.com']);
    expect(find.text('Resend available in 60s'), findsOneWidget);
  });

  test('confirmed auth state clears pending confirmation state', () async {
    SharedPreferences.setMockInitialValues({
      'pendingSignupEmailV1': 'learner@example.com',
    });
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    harness.auth.handleAuthState(
      AuthState(
        AuthChangeEvent.signedIn,
        _verifiedResponse('learner@example.com').session,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(harness.auth.isAuthenticated, isTrue);
    expect(harness.auth.isEmailVerified, isTrue);
    expect(harness.auth.hasPendingSignupVerification, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('pendingSignupEmailV1'), isFalse);
  });

  testWidgets('confirmation screen routes verified deep-link session to root', (
    tester,
  ) async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_navigationApp(harness.auth));
    harness.auth.handleAuthState(
      AuthState(
        AuthChangeEvent.signedIn,
        _verifiedResponse('learner@example.com').session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verified destination'), findsOneWidget);
    expect(find.byType(SignupConfirmationScreen), findsNothing);
  });

  test('passwordless sign-in OTP remains a separate email-code flow', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    final success = await harness.auth.verifySignInOtp(
      email: 'learner@example.com',
      token: '123456',
    );

    expect(success, isTrue);
    expect(harness.gateway.verifiedEmail, 'learner@example.com');
    expect(harness.gateway.verifiedToken, '123456');
  });

  test('mobile auth callback remains compatible with the configured scheme', () {
    expect(AppEnvironment.mobileAuthScheme, 'io.promptwise.app');
    expect(AppEnvironment.mobileAuthHost, 'auth-callback');
    expect(
      AppEnvironment.emailConfirmationRedirectUrl,
      'io.promptwise.app://auth-callback/',
    );
    expect(
      AppEnvironment.passwordRecoveryRedirectUrl,
      'io.promptwise.app://auth-callback/',
    );
  });
}

Future<_AuthHarness> _createHarness({
  Object? resendError,
  Object? signInError,
}) async {
  final gateway = _FakeAuthGateway(
    resendError: resendError,
    signInError: signInError,
  );
  final auth = AuthController(repository: gateway);
  await auth.init();
  return _AuthHarness(auth, gateway);
}

class _AuthHarness {
  final AuthController auth;
  final _FakeAuthGateway gateway;

  const _AuthHarness(this.auth, this.gateway);

  Future<void> dispose() async {
    auth.dispose();
    await gateway.dispose();
  }
}

Widget _screenApp(AuthController auth, Widget home) {
  return ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(home: home),
  );
}

Widget _navigationApp(AuthController auth) {
  return ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(
      initialRoute: AppRoutes.confirmEmail,
      routes: {
        AppRoutes.root: (_) =>
            const Scaffold(body: Center(child: Text('Verified destination'))),
        AppRoutes.confirmEmail: (_) => const SignupConfirmationScreen(
          email: 'learner@example.com',
        ),
        AppRoutes.login: (_) => const Scaffold(body: Text('Sign in')),
      },
    ),
  );
}

class _FakeAuthGateway implements AuthGateway {
  final _authStates = StreamController<AuthState>.broadcast();
  final Object? resendError;
  final Object? signInError;

  String? signupEmail;
  String? verifiedEmail;
  String? verifiedToken;
  final resentSignupEmails = <String>[];

  _FakeAuthGateway({this.resendError, this.signInError});

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get authStateChanges => _authStates.stream;

  @override
  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    signupEmail = email.trim();
    return AuthResponse(user: _user(email.trim(), confirmed: false));
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final error = signInError;
    if (error != null) throw error;
    return _verifiedResponse(email.trim());
  }

  @override
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifiedEmail = email;
    verifiedToken = token;
    return _verifiedResponse(email);
  }

  @override
  Future<void> resendSignupConfirmation(String email) async {
    final error = resendError;
    if (error != null) throw error;
    resentSignupEmails.add(email);
  }

  @override
  Future<AppProfile?> fetchMyProfile(String userId) async {
    return AppProfile(
      id: userId,
      email: 'learner@example.com',
      fullName: 'Prompt Wise',
      role: AppRole.learner,
    );
  }

  Future<void> dispose() => _authStates.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthResponse _verifiedResponse(String email) {
  final user = _user(email, confirmed: true);
  return AuthResponse(
    user: user,
    session: Session(
      accessToken: 'access-token',
      tokenType: 'bearer',
      user: user,
      refreshToken: 'refresh-token',
      expiresIn: 3600,
    ),
  );
}

User _user(String email, {required bool confirmed}) {
  return User(
    id: 'user-1',
    appMetadata: const {},
    userMetadata: const {'full_name': 'Prompt Wise'},
    aud: 'authenticated',
    createdAt: '2026-09-01T00:00:00.000Z',
    email: email,
    emailConfirmedAt: confirmed ? '2026-09-01T00:01:00.000Z' : null,
  );
}

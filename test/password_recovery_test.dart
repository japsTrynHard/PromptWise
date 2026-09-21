import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:promptwise/app.dart';
import 'package:promptwise/core/routes/app_routes.dart';
import 'package:promptwise/core/routes/auth_callback.dart';
import 'package:promptwise/data/models/app_profile.dart';
import 'package:promptwise/data/repositories/auth_repository.dart';
import 'package:promptwise/presentation/controllers/auth_controller.dart';
import 'package:promptwise/presentation/controllers/theme_controller.dart';
import 'package:promptwise/presentation/screens/auth/forgot_password_screen.dart';
import 'package:promptwise/presentation/screens/auth/reset_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthGateway gateway;
  late AuthController auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    gateway = _FakeAuthGateway();
    auth = AuthController(repository: gateway);
    await auth.init();
  });

  tearDown(() async {
    auth.dispose();
    await gateway.dispose();
  });

  test(
    'password reset request uses the link request without an OTP purpose',
    () async {
      final success = await auth.sendPasswordReset(' learner@example.com ');

      expect(success, isTrue);
      expect(gateway.lastResetEmail, 'learner@example.com');
      expect(auth.hasPendingSignupVerification, isFalse);
      expect(auth.isPasswordRecovery, isFalse);
    },
  );

  test('PASSWORD_RECOVERY auth event activates the recovery state', () {
    auth.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );

    expect(auth.isPasswordRecovery, isTrue);
    expect(auth.hasPendingSignupVerification, isFalse);
  });

  testWidgets('forgot password confirms that a reset link was sent', (
    tester,
  ) async {
    await tester.pumpWidget(_screenApp(auth, const ForgotPasswordScreen()));

    await tester.enterText(find.byType(TextFormField), 'learner@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(gateway.lastResetEmail, 'learner@example.com');
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'We sent you a password reset link. Open your email and follow the link to choose a new password.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('6-digit'), findsNothing);
  });

  testWidgets('recovery state routes to exactly one reset password screen', (
    tester,
  ) async {
    await tester.pumpWidget(_promptWiseApp(auth));
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordScreen), findsNothing);

    auth.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.textContaining('6-digit'), findsNothing);
  });

  testWidgets('reset password rejects a mismatched confirmation', (
    tester,
  ) async {
    auth.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    await tester.pumpWidget(_promptWiseApp(auth));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'new-password-123');
    await tester.enterText(fields.at(1), 'different-password');
    await tester.tap(find.text('Save password'));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(gateway.updatedPasswords, isEmpty);
    expect(auth.isPasswordRecovery, isTrue);
  });

  testWidgets('successful update clears recovery and leaves the reset screen', (
    tester,
  ) async {
    auth.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    await tester.pumpWidget(_promptWiseApp(auth));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'new-password-123');
    await tester.enterText(fields.at(1), 'new-password-123');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(gateway.updatedPasswords, ['new-password-123']);
    expect(auth.isPasswordRecovery, isFalse);
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });

  for (final location in [
    'http://localhost:3000/?error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired'
        '#error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired&sb=',
    '/error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired',
  ]) {
    testWidgets('expired email callback opens reset-link form: $location', (
      tester,
    ) async {
      await tester.pumpWidget(_routeApp(auth, location));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.text(AuthCallback.expiredLinkMessage), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);
      expect(find.text('Page not found'), findsNothing);
      expect(find.text('Save password'), findsNothing);

      await tester.enterText(find.byType(TextFormField), 'learner@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(gateway.lastResetEmail, 'learner@example.com');
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text(AuthCallback.expiredLinkMessage), findsNothing);
    });
  }

  for (final location in [
    '/?code=unused-test-code',
    '/access_token=unused-test-token&type=recovery',
  ]) {
    testWidgets('callback URL alone cannot authorize a reset: $location', (
      tester,
    ) async {
      await tester.pumpWidget(_routeApp(auth, location));
      await tester.pumpAndSettle();

      expect(find.text('Page not found'), findsNothing);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.text('Save password'), findsNothing);
      expect(auth.isPasswordRecovery, isFalse);
    });
  }

  testWidgets('unrelated unknown routes still show page not found', (
    tester,
  ) async {
    await tester.pumpWidget(_routeApp(auth, '/missing-page?source=email'));
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets('existing sign-in does not authorize an expired reset link', (
    tester,
  ) async {
    auth.handleAuthState(
      AuthState(AuthChangeEvent.signedIn, _signedInSession()),
    );
    await tester.pumpWidget(
      _routeApp(auth, '/?error=access_denied&error_code=otp_expired'),
    );
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.isPasswordRecovery, isFalse);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('New password'), findsNothing);
    expect(find.text('Save password'), findsNothing);
    expect(gateway.updatedPasswords, isEmpty);
  });

  testWidgets('opening reset screen directly offers a fresh link', (
    tester,
  ) async {
    await tester.pumpWidget(_routeApp(auth, AppRoutes.resetPassword));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save password'), findsNothing);
    await tester.tap(find.text('Send a new reset link'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets(
    'SDK callback error redirects and clears after requesting a link',
    (tester) async {
      await tester.pumpWidget(_promptWiseApp(auth));
      await tester.pumpAndSettle();

      // getSessionFromUrl places URL error_code in statusCode in this SDK.
      gateway.emitError(
        const AuthException(
          'Email link is invalid or has expired',
          statusCode: 'otp_expired',
          code: 'access_denied',
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.authLinkErrorMessage, AuthCallback.expiredLinkMessage);
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.text(AuthCallback.expiredLinkMessage), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'learner@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(auth.authLinkErrorMessage, isNull);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text(AuthCallback.expiredLinkMessage), findsNothing);

      auth.handleAuthState(
        const AuthState(AuthChangeEvent.passwordRecovery, null),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text('Choose a new password'), findsOneWidget);
    },
  );

  testWidgets('a rejected callback closes an already open password form', (
    tester,
  ) async {
    auth.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    await tester.pumpWidget(_promptWiseApp(auth));
    await tester.pumpAndSettle();
    expect(find.text('Save password'), findsOneWidget);

    gateway.emitError(
      const AuthException(
        'Email link is invalid or has expired',
        statusCode: 'otp_expired',
        code: 'access_denied',
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.isPasswordRecovery, isFalse);
    expect(find.text('Save password'), findsNothing);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(gateway.updatedPasswords, isEmpty);
  });

  testWidgets('leaving an error allows another invalid link to open recovery', (
    tester,
  ) async {
    await tester.pumpWidget(_promptWiseApp(auth));
    await tester.pumpAndSettle();
    const error = AuthException(
      'Email link is invalid or has expired',
      statusCode: 'otp_expired',
      code: 'access_denied',
    );
    gateway.emitError(error);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(auth.authLinkErrorMessage, isNull);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.text(AuthCallback.expiredLinkMessage), findsNothing);

    gateway.emitError(error);
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text(AuthCallback.expiredLinkMessage), findsOneWidget);
  });

  testWidgets('replayed recovery event opens reset form on startup', (
    tester,
  ) async {
    final replayGateway = _FakeAuthGateway(
      initialAuthState: const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    final replayAuth = AuthController(repository: replayGateway);
    addTearDown(() async {
      replayAuth.dispose();
      await replayGateway.dispose();
    });
    await replayAuth.init();

    await tester.pumpWidget(_promptWiseApp(replayAuth));
    await tester.pumpAndSettle();

    expect(replayAuth.isPasswordRecovery, isTrue);
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('Save password'), findsOneWidget);
  });
}

Widget _screenApp(AuthController auth, Widget home) {
  return ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(home: home),
  );
}

Widget _promptWiseApp(AuthController auth) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
    ],
    child: const PromptWiseApp(),
  );
}

Widget _routeApp(AuthController auth, String location) {
  return ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(
      initialRoute: location,
      onGenerateRoute: AppRoutes.generateRoute,
      onGenerateInitialRoutes: (_) => [
        AppRoutes.generateRoute(RouteSettings(name: location)),
      ],
    ),
  );
}

Session _signedInSession() => Session(
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  tokenType: 'bearer',
  user: User(
    id: 'learner-1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-09-01T00:00:00Z',
    email: 'learner@example.com',
    emailConfirmedAt: '2026-09-01T00:01:00Z',
  ),
);

class _FakeAuthGateway implements AuthGateway {
  final _authStates = StreamController<AuthState>.broadcast();
  final AuthState? initialAuthState;
  final updatedPasswords = <String>[];
  String? lastResetEmail;

  _FakeAuthGateway({this.initialAuthState});

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get authStateChanges => initialAuthState == null
      ? _authStates.stream
      : Stream<AuthState>.value(initialAuthState!);

  void emitError(Object error) =>
      _authStates.addError(error, StackTrace.current);

  @override
  Future<AppProfile?> fetchMyProfile(String userId) async => AppProfile(
    id: userId,
    email: 'learner@example.com',
    fullName: 'Learner',
    role: AppRole.learner,
  );

  @override
  Future<void> sendPasswordReset(String email) async {
    lastResetEmail = email;
  }

  @override
  Future<void> updatePassword(String password) async {
    updatedPasswords.add(password);
  }

  Future<void> dispose() => _authStates.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

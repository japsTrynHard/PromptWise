import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:promptwise/app.dart';
import 'package:promptwise/data/repositories/auth_repository.dart';
import 'package:promptwise/presentation/controllers/auth_controller.dart';
import 'package:promptwise/presentation/controllers/theme_controller.dart';
import 'package:promptwise/presentation/screens/auth/forgot_password_screen.dart';
import 'package:promptwise/presentation/screens/auth/reset_password_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late _FakeAuthGateway gateway;
  late AuthController auth;

  setUp(() async {
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
      expect(auth.pendingOtpPurpose, isNull);
      expect(auth.isPasswordRecovery, isFalse);
    },
  );

  test('PASSWORD_RECOVERY auth event activates the recovery state', () {
    auth.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );

    expect(auth.isPasswordRecovery, isTrue);
    expect(auth.pendingOtpPurpose, isNull);
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

class _FakeAuthGateway implements AuthGateway {
  final _authStates = StreamController<AuthState>.broadcast();
  final updatedPasswords = <String>[];
  String? lastResetEmail;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get authStateChanges => _authStates.stream;

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
